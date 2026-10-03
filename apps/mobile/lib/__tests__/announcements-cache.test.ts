import { beforeEach, describe, expect, it, vi } from 'vitest';
const disk = vi.hoisted(() => new Map<string, string>());
vi.mock('expo-secure-store', () => ({ getItemAsync: async (key: string) => disk.get(key) ?? null, setItemAsync: async (key: string, value: string) => { disk.set(key, value); }, deleteItemAsync: async (key: string) => { disk.delete(key); } }));
const { ANNOUNCEMENT_CACHE_KEY, applyLocalRead, resolveAnnouncementFeed, loadAnnouncementCache, flushPendingReads, queueRead } = await import('../announcements');
const scope = { tenantId: '75000000-0000-4000-8000-000000000001', userId: '75000000-0000-4000-8000-000000000906', memberId: '75000000-0000-4000-8000-000000000101' };
const id = '75000000-0000-4000-8000-000000000201';
const card = { announcementId: id, kind: 'transactional' as const, title: 'Notice', body: 'Plain', imageUrl: null, versionNo: 2, publishedAt: '2026-10-02T00:00:00Z', editedAt: '2026-10-02T01:00:00Z', expiresAt: null, changeNote: 'Changed time', readState: 'updated' as const, readAt: '2026-10-02T00:30:00Z' };
const cached = () => ({ scope, fetchedAt: '2026-10-02T01:30:00Z', announcements: [card], pendingReads: [] as Array<{ announcementId: string; versionNo: number }> });
beforeEach(() => disk.clear());
describe('ANC-021 scope-bound saved feed and pending reads', () => {
  it('fresh including empty wins; failed fetch uses same-scope saved copy only', () => {
    expect(ANNOUNCEMENT_CACHE_KEY).toBe('gymloop.announcements-cache');
    const cache = cached();
    expect(resolveAnnouncementFeed({ fetched: [], cached: cache, scope }).cards).toEqual([]);
    expect(resolveAnnouncementFeed({ fetched: [card], cached: cache, scope }).stale).toBe(false);
    expect(resolveAnnouncementFeed({ fetched: null, cached: cache, scope })).toEqual({ cards: [card], stale: true, fetchedAt: cache.fetchedAt });
    for (const key of ['tenantId', 'userId', 'memberId'] as const) expect(resolveAnnouncementFeed({ fetched: null, cached: cache, scope: { ...scope, [key]: 'other' } })).toEqual({ cards: [], stale: false, fetchedAt: null });
  });
  it('optimistic opening affects only the matching announcement version without mutating input', () => {
    const cards = [card, { ...card, announcementId: '75000000-0000-4000-8000-000000000202' }];
    expect(applyLocalRead(cards, id, 1)).toEqual(cards);
    const updated = applyLocalRead(cards, id, 2); expect(updated[0]?.readState).toBe('read'); expect(updated[1]?.readState).toBe('updated'); expect(cards[0]?.readState).toBe('updated');
  });
  it('loads the pinned value but ignores corrupt or foreign cache', async () => {
    disk.set(ANNOUNCEMENT_CACHE_KEY, JSON.stringify(cached())); expect(await loadAnnouncementCache(scope)).toMatchObject(cached());
    expect(await loadAnnouncementCache({ ...scope, tenantId: 'other' })).toBeNull();
    for (const raw of ['{', '{}', 'null']) { disk.set(ANNOUNCEMENT_CACHE_KEY, raw); expect(await loadAnnouncementCache(scope)).toBeNull(); }
  });
  it('flush posts each exact version once and removes true/false receipts', async () => {
    const cache = cached(); cache.pendingReads = [{ announcementId: id, versionNo: 1 }, { announcementId: id, versionNo: 2 }]; disk.set(ANNOUNCEMENT_CACHE_KEY, JSON.stringify(cache));
    const post = vi.fn(async (_path: string, body: { versionNo: number }) => ({ ok: true, data: { recorded: body.versionNo === 2 } }));
    await flushPendingReads({ post } as never, scope);
    expect(post.mock.calls).toEqual([[`/api/member/announcements/${id}/read`, { versionNo: 1 }], [`/api/member/announcements/${id}/read`, { versionNo: 2 }]]);
    expect((await loadAnnouncementCache(scope))?.pendingReads).toEqual([]);
    await flushPendingReads({ post } as never, scope); expect(post).toHaveBeenCalledTimes(2);
  });
  it('a server 404 drops a vanished announcement read rather than retrying forever', async () => {
    const cache = cached(); cache.pendingReads = [{ announcementId: id, versionNo: 2 }];
    disk.set(ANNOUNCEMENT_CACHE_KEY, JSON.stringify(cache));
    const post = vi.fn(async () => ({ ok: false, status: 404, error: { code: 'announcement_not_found', message: 'Unavailable' } }));
    await flushPendingReads({ post } as never, scope);
    expect(post).toHaveBeenCalledTimes(1);
    expect((await loadAnnouncementCache(scope))?.pendingReads).toEqual([]);
  });
  it('a network failure keeps pending read; foreign scope sends nothing', async () => {
    const cache = cached(); cache.pendingReads = [{ announcementId: id, versionNo: 2 }]; disk.set(ANNOUNCEMENT_CACHE_KEY, JSON.stringify(cache));
    const post = vi.fn(async () => { throw new Error('offline'); });
    await flushPendingReads({ post } as never, { ...scope, userId: 'other' }); expect(post).not.toHaveBeenCalled();
    await flushPendingReads({ post } as never, scope); expect((await loadAnnouncementCache(scope))?.pendingReads).toEqual(cache.pendingReads);
  });
});

it('ANC-021 concurrent deliveries preserve a newly queued exact version without requiring single HTTP dispatch', async () => {
  const cache = cached(); cache.pendingReads = [{ announcementId: id, versionNo: 2 }];
  disk.set(ANNOUNCEMENT_CACHE_KEY, JSON.stringify(cache));
  const acknowledgements: Array<() => void> = [];
  const delivered = new Set<string>();
  const post = vi.fn((path: string, body: { versionNo: number }) => new Promise(resolve => {
    acknowledgements.push(() => { delivered.add(`${path}:${body.versionNo}`); resolve({ ok: true, data: { recorded: true } }); });
  }));
  const first = flushPendingReads({ post } as never, scope); const second = flushPendingReads({ post } as never, scope);
  await vi.waitFor(() => expect(acknowledgements.length).toBeGreaterThan(0));
  await queueRead(scope, id, 3);
  acknowledgements.forEach(acknowledge => acknowledge());
  // A serialized second delivery may start after the first completes.
  for (let step = 0; step < 40; step++) { await Promise.resolve(); acknowledgements.forEach(acknowledge => acknowledge()); }
  await Promise.all([first, second]);
  const remaining = (await loadAnnouncementCache(scope))?.pendingReads ?? [];
  expect(remaining).not.toContainEqual({ announcementId: id, versionNo: 2 });
  // The new pair must either remain queued or have its own successful delivery.
  expect(remaining.some(value => value.announcementId === id && value.versionNo === 3) || delivered.has(`/api/member/announcements/${id}/read:3`)).toBe(true);
});
