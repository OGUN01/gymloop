import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  flushPendingReads, loadAnnouncementCache, queueRead, saveAnnouncementCache,
} from '../../apps/mobile/lib/announcements';

const disk = vi.hoisted(() => ({ value: null as string | null, writes: vi.fn() }));
vi.mock('expo-secure-store', () => ({
  getItemAsync: vi.fn(async () => disk.value),
  setItemAsync: vi.fn(async (_key: string, value: string) => { disk.value = value; disk.writes(value); }),
  deleteItemAsync: vi.fn(async () => { disk.value = null; }),
}));
const scope = {
  tenantId: '75900000-0000-4000-8000-000000000001',
  userId: '75900000-0000-4000-8000-000000000101',
  memberId: '75900000-0000-4000-8000-000000000201',
};
const announcementId = '75900000-0000-4000-8000-000000000501';
const cache = () => ({
  scope, fetchedAt: '2026-10-03T06:00:00Z', announcements: [],
  pendingReads: [{ announcementId, versionNo: 1 }],
});
const deferred = <T>() => {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((finish) => { resolve = finish; });
  return { promise, resolve };
};
beforeEach(() => { disk.value = null; vi.clearAllMocks(); });

describe('independent ANC exact-version cache lifetime', () => {
  it('a retained save and queue callback cannot write after the caller becomes obsolete', async () => {
    await saveAnnouncementCache(cache());
    const stored = disk.value;
    disk.writes.mockClear();
    await saveAnnouncementCache({ ...cache(), pendingReads: [] }, () => false);
    await queueRead(scope, announcementId, 2, () => false);
    expect(disk.value).toBe(stored);
    expect(disk.writes).not.toHaveBeenCalled();
  });
  it('a retained flush cannot deliver another lifetime or mutate its cache', async () => {
    await saveAnnouncementCache(cache());
    const post = vi.fn();
    const stored = disk.value;
    await flushPendingReads({ post } as unknown as Parameters<typeof flushPendingReads>[0], scope, () => false);
    expect(post).not.toHaveBeenCalled();
    expect(disk.value).toBe(stored);
  });
  it('in-flight completion cannot overwrite a replacement member cache', async () => {
    await saveAnnouncementCache(cache());
    const pending = deferred<{ ok: true; data: { recorded: boolean } }>();
    const entered = deferred<void>();
    let current = true;
    const post = vi.fn(() => { entered.resolve(); return pending.promise; });
    const flushing = flushPendingReads({ post } as unknown as Parameters<typeof flushPendingReads>[0], scope, () => current);
    await entered.promise;
    current = false;
    const nextScope = { ...scope, memberId: '75900000-0000-4000-8000-000000000202' };
    await saveAnnouncementCache({ ...cache(), scope: nextScope, pendingReads: [] });
    const replacement = disk.value;
    pending.resolve({ ok: true, data: { recorded: true } });
    await flushing;
    expect(disk.value).toBe(replacement);
    expect(await loadAnnouncementCache(scope)).toBeNull();
  });
  it('delivery of an earlier version preserves a later version queued during the request', async () => {
    await saveAnnouncementCache(cache());
    const pending = deferred<{ ok: true; data: { recorded: boolean } }>();
    const entered = deferred<void>();
    const post = vi.fn(() => { entered.resolve(); return pending.promise; });
    const flushing = flushPendingReads({ post } as unknown as Parameters<typeof flushPendingReads>[0], scope);
    await entered.promise;
    await queueRead(scope, announcementId, 2);
    await queueRead(scope, announcementId, 2);
    pending.resolve({ ok: true, data: { recorded: true } });
    await flushing;
    expect((await loadAnnouncementCache(scope))?.pendingReads).toEqual([{ announcementId, versionNo: 2 }]);
    expect(post).toHaveBeenCalledWith(`/api/member/announcements/${announcementId}/read`, { versionNo: 1 });
  });
  it.each(['false', '404'] as const)('terminal %s acknowledgement removes only its exact queued version', async (outcome) => {
    await saveAnnouncementCache(cache());
    const post = vi.fn(async () => {
      if (outcome === '404') return { ok: false, error: { status: 404, code: 'announcement_not_found', message: 'Not found' } };
      return { ok: true, data: { recorded: false } };
    });
    await flushPendingReads({ post } as unknown as Parameters<typeof flushPendingReads>[0], scope);
    expect((await loadAnnouncementCache(scope))?.pendingReads).toEqual([]);
  });
  it('overlapping deliveries never erase a newer queued version', async () => {
    await saveAnnouncementCache(cache());
    const completion = deferred<{ ok: true; data: { recorded: boolean } }>();
    const entered = deferred<void>();
    const post = vi.fn(() => { entered.resolve(); return completion.promise; });
    const api = { post } as unknown as Parameters<typeof flushPendingReads>[0];
    const a = flushPendingReads(api, scope);
    const b = flushPendingReads(api, scope);
    await entered.promise;
    await queueRead(scope, announcementId, 2);
    completion.resolve({ ok: true, data: { recorded: true } });
    await Promise.all([a, b]);
    expect((await loadAnnouncementCache(scope))?.pendingReads).toEqual([{ announcementId, versionNo: 2 }]);
  });
});

