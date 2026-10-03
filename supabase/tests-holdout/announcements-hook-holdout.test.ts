import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { GymloopIdentity } from '../../packages/shared/src/api/identity';
import { useAnnouncements } from '../../apps/mobile/lib/use-announcements';

const harness = vi.hoisted(() => {
  const post = vi.fn();
  return {
  slots: [] as unknown[], cursor: 0,
  effects: [] as Array<() => void>, cleanups: [] as Array<(() => void) | undefined>,
  identity: { kind: 'unlinked' } as GymloopIdentity,
  post, api: { post }, load: vi.fn(), save: vi.fn(), queue: vi.fn(), flush: vi.fn(),
  disk: null as string | null,
  actualCache: null as null | typeof import('../../apps/mobile/lib/announcements'),
}; });
vi.mock('../../apps/mobile/lib/mobile-context', () => ({
  useMobile: () => ({ identity: harness.identity, api: harness.api }),
}));
vi.mock('../../apps/mobile/lib/announcements', async (original) => {
  const actual = await original<typeof import('../../apps/mobile/lib/announcements')>();
  harness.actualCache = actual;
  return {
    ...actual, loadAnnouncementCache: harness.load, saveAnnouncementCache: harness.save,
    queueRead: harness.queue, flushPendingReads: harness.flush,
  };
});
vi.mock('expo-secure-store', () => ({
  getItemAsync: async () => harness.disk,
  setItemAsync: async (_key: string, value: string) => { harness.disk = value; },
  deleteItemAsync: async () => { harness.disk = null; },
}));
vi.mock('react', () => {
  const memo = (factory: () => unknown, deps?: unknown[]) => {
    const index = harness.cursor++;
    const previous = harness.slots[index] as { deps?: unknown[]; value: unknown } | undefined;
    if (!previous || !deps || deps.some((value, i) => !Object.is(value, previous.deps?.[i]))) {
      harness.slots[index] = { deps, value: factory() };
    }
    return (harness.slots[index] as { value: unknown }).value;
  };
  return {
    useState: (initial: unknown) => {
      const index = harness.cursor++;
      if (!(index in harness.slots)) harness.slots[index] = typeof initial === 'function' ? initial() : initial;
      return [harness.slots[index], (value: unknown) => {
        harness.slots[index] = typeof value === 'function' ? value(harness.slots[index]) : value;
      }];
    },
    useRef: (value: unknown) => memo(() => ({ current: value }), []),
    useMemo: memo,
    useCallback: (callback: unknown, deps?: unknown[]) => memo(() => callback, deps),
    useEffect: (effect: () => (() => void) | void, deps?: unknown[]) => {
      const index = harness.cursor++;
      const old = harness.slots[index] as unknown[] | undefined;
      if (!old || !deps || deps.some((value, i) => !Object.is(value, old[i]))) {
        harness.slots[index] = deps;
        harness.effects.push(() => {
          harness.cleanups[index]?.();
          harness.cleanups[index] = effect() ?? undefined;
        });
      }
    },
  };
});
const announcementId = '75900000-0000-4000-8000-000000000501';
const member = (suffix: string): GymloopIdentity => ({
  kind: 'member', tenantId: '75900000-0000-4000-8000-000000000001',
  userId: `75900000-0000-4000-8000-0000000001${suffix}`,
  memberId: `75900000-0000-4000-8000-0000000002${suffix}`,
});
const card = (versionNo = 1, readState: 'unread' | 'updated' | 'read' = 'unread') => ({
  announcementId, kind: 'transactional' as const, title: 'Closure', body: 'Closed Sunday',
  imageUrl: null, versionNo, publishedAt: '2026-10-03T06:00:00Z',
  editedAt: versionNo === 1 ? null : '2026-10-03T07:00:00Z',
  changeNote: versionNo === 1 ? null : 'Closure clarified', expiresAt: null, readAt: null, readState,
});
const feed = (cards = [card()]) => ({ ok: true, data: { asOf: '2026-10-03T08:00:00Z', announcements: cards } });
const deferred = <T>() => {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((finish) => { resolve = finish; });
  return { promise, resolve };
};
const render = () => { harness.cursor = 0; return useAnnouncements(); };
const settle = async () => {
  let value = render();
  for (let round = 0; round < 48; round += 1) {
    for (const effect of harness.effects.splice(0)) effect();
    await Promise.resolve();
    value = render();
  }
  return value;
};
beforeEach(() => {
  for (const cleanup of harness.cleanups) cleanup?.();
  harness.slots = []; harness.effects = []; harness.cleanups = []; harness.cursor = 0;
  vi.resetAllMocks();
  harness.disk = null;
  harness.identity = member('01');
  harness.load.mockResolvedValue(null); harness.save.mockResolvedValue(undefined);
  harness.queue.mockResolvedValue(undefined); harness.flush.mockResolvedValue(undefined);
  harness.post.mockResolvedValue(feed());
});

describe('independent ANC complete caller hook lifetime', () => {
  it.each(['tenantId', 'userId', 'memberId'] as const)('%s transition hides preceding cards before new fetch settles', async (dimension) => {
    const original = member('01');
    if (original.kind !== 'member') throw new Error('invalid fixture');
    const replacement = {
      tenantId: '75900000-0000-4000-8000-000000000002',
      userId: '75900000-0000-4000-8000-000000000102',
      memberId: '75900000-0000-4000-8000-000000000202',
    };
    const changed = { ...original, [dimension]: replacement[dimension] };
      harness.identity = original; harness.post.mockResolvedValue(feed([card(1, 'read')]));
      expect((await settle()).cards).toHaveLength(1);
      const waiting = deferred<ReturnType<typeof feed>>();
      harness.post.mockReturnValue(waiting.promise);
      harness.identity = changed;
      expect(render().cards).toEqual([]);
      expect((await settle()).cards).toEqual([]);
      waiting.resolve(feed([]));
      await settle();
  });
  it('retained reload and markRead cannot issue work for a replacement caller or after unmount', async () => {
    const previous = await settle();
    harness.identity = member('02');
    await settle();
    harness.post.mockClear(); harness.queue.mockClear();
    await previous.reload(); await previous.markRead(announcementId, 1);
    expect(harness.post).not.toHaveBeenCalled(); expect(harness.queue).not.toHaveBeenCalled();
    const current = render();
    for (const cleanup of harness.cleanups) cleanup?.();
    await current.reload(); await current.markRead(announcementId, 1);
    expect(harness.post).not.toHaveBeenCalled(); expect(harness.queue).not.toHaveBeenCalled();
  });
  it.each(['false', '404'] as const)('current version %s response cannot leave phantom read state', async (outcome) => {
    const initial = await settle();
    expect(initial.cards).toEqual([card()]);
    harness.post.mockImplementation(async (path: string) => path.endsWith('/feed') ? feed() : outcome === 'false'
      ? { ok: true, data: { recorded: false } }
      : { ok: false, error: { code: 'announcement_not_found', message: 'Not found', status: 404 } });
    await initial.markRead(announcementId, 1);
    expect((await settle()).cards[0]?.readState).toBe('unread');
  });
  it('authoritative newer version replaces optimistic read of the previous version', async () => {
    const initial = await settle();
    expect(initial.cards).toEqual([card()]);
    harness.post.mockResolvedValue({ ok: true, data: { recorded: true } });
    await initial.markRead(announcementId, 1);
    harness.post.mockResolvedValue(feed([card(2, 'updated')]));
    await render().reload();
    expect((await settle()).cards).toEqual([card(2, 'updated')]);
  });
  it.each(['false', '404'] as const)('persisted same-scope read optimism cannot survive a terminal %s acknowledgement', async (outcome) => {
    const actual = harness.actualCache;
    if (!actual || harness.identity.kind !== 'member') throw new Error('invalid cache fixture');
    const scope = {
      tenantId: harness.identity.tenantId, userId: harness.identity.userId,
      memberId: harness.identity.memberId,
    };
    harness.load.mockImplementation(actual.loadAnnouncementCache);
    harness.save.mockImplementation(actual.saveAnnouncementCache);
    harness.queue.mockImplementation(actual.queueRead);
    harness.flush.mockImplementation(actual.flushPendingReads);
    await actual.saveAnnouncementCache({
      scope, fetchedAt: '2026-10-03T06:00:00Z', announcements: [card(1, 'read')],
      pendingReads: [{ announcementId, versionNo: 1 }],
    });
    const refused = outcome === 'false'
      ? { ok: true, data: { recorded: false } }
      : { ok: false, error: { code: 'announcement_not_found', message: 'Not found', status: 404 } };
    harness.post.mockImplementation(async (path: string) => path.endsWith('/feed') ? feed() : refused);
    const initial = await settle();
    expect(initial.cards).toEqual([card()]);
    expect(await actual.loadAnnouncementCache(scope)).not.toBeNull();
    await initial.markRead(announcementId, 1);
    expect((await settle()).cards[0]?.readState).toBe('unread');
    harness.post.mockImplementation(async (path: string) => path.endsWith('/feed') ? feed([card(2, 'updated')]) : refused);
    await render().reload();
    expect((await settle()).cards).toEqual([card(2, 'updated')]);
    expect((await actual.loadAnnouncementCache(scope))?.announcements).toEqual([card(2, 'updated')]);
  });
});
