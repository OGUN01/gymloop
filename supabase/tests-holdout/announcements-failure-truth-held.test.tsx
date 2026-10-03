// Independent approved failure-truth holdout. Only public declarations and own held hosts read.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ANNOUNCEMENT_REFUSAL_COPY, announcementRefusalMessage } from '../../packages/shared/src/api/announcements';
import { useAnnouncements } from '../../apps/mobile/lib/use-announcements';
import * as cacheModule from '../../apps/mobile/lib/announcements';
import { useAnnouncementCommand } from '../../apps/web/lib/use-announcement-command';
import { announcementCommand } from '../../apps/web/lib/announcement-http';
import { POST as discardRoute } from '../../apps/web/app/api/announcements/[announcementId]/discard/route';

type Scope = { tenantId: string; userId: string; memberId: string };
type Cell = { value?: unknown; deps?: unknown[]; cleanup?: (() => void) | undefined };
const h = vi.hoisted(() => {
  const post = vi.fn();
  return { cells: [] as Cell[], cursor: 0, effects: [] as Array<() => void>, identity: {} as Record<string, unknown>, api: { post }, post,
    value: null as string | null, get: vi.fn(), set: vi.fn(), remove: vi.fn(), network: vi.fn(), fetch: vi.fn(), refresh: vi.fn(), preview: false, staff: vi.fn(), member: vi.fn(), rpc: vi.fn() };
});
vi.mock('../../apps/web/lib/api', async original => ({ ...await original<Record<string, unknown>>(), staffSession: (...args: unknown[]) => h.staff(...args), memberSession: (...args: unknown[]) => h.member(...args) }));
vi.mock('../../apps/web/lib/media', () => ({ memberMediaUrl: vi.fn(() => { throw new Error('Unexpected media read'); }) }));
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => ({ identity: h.identity, api: h.api }) }));
vi.mock('expo-secure-store', () => ({ getItemAsync: (...args: unknown[]) => h.get(...args), setItemAsync: (...args: unknown[]) => h.set(...args), deleteItemAsync: (...args: unknown[]) => h.remove(...args) }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: () => h.network() }));
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: h.refresh }) }));
vi.mock('../../apps/web/app/preview-context', () => ({ usePreviewReadOnly: () => h.preview }));
vi.mock('react', async original => {
  const actual = await original<Record<string, unknown>>();
  const cell = () => { const index = h.cursor++; return h.cells[index] ?? (h.cells[index] = {}); };
  const memo = (fn: () => unknown, deps?: unknown[]) => { const slot = cell(); if (!slot.deps || !deps || deps.length !== slot.deps.length || deps.some((value, index) => !Object.is(value, slot.deps?.[index]))) { slot.value = fn(); slot.deps = deps; } return slot.value; };
  const effect = (fn: () => unknown, deps?: unknown[]) => { const slot = cell(); if (!slot.deps || !deps || deps.length !== slot.deps.length || deps.some((value, index) => !Object.is(value, slot.deps?.[index]))) { slot.deps = deps; h.effects.push(() => { slot.cleanup?.(); const result = fn(); slot.cleanup = typeof result === 'function' ? result as () => void : undefined; }); } };
  return { ...actual, useState: (initial: unknown) => { const slot = cell(); if (!Object.hasOwn(slot, 'value')) slot.value = typeof initial === 'function' ? initial() : initial; return [slot.value, (value: unknown) => { slot.value = typeof value === 'function' ? value(slot.value) : value; }]; }, useMemo: memo, useCallback: (fn: unknown, deps?: unknown[]) => memo(() => fn, deps), useRef: (value: unknown) => memo(() => ({ current: value }), []), useEffect: effect, useLayoutEffect: effect };
});

const id = (n: number) => `77940000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const scopeA: Scope = { tenantId: id(1), userId: id(2), memberId: id(3) };
const scopeB: Scope = { tenantId: id(4), userId: id(5), memberId: id(6) };
const secret = 'PRIVATE_unknown_command_database_token_779';
const unknownCopy = 'The result could not be confirmed. Reload to check whether the announcement was saved.';
const savedAt = '2026-10-03T06:00:00Z';
function card(title = 'Held saved closure') { return { announcementId: id(50), kind: 'transactional' as const, title, body: 'The gym closes Sunday.', imageUrl: null, versionNo: 1, publishedAt: '2026-10-02T06:00:00Z', editedAt: null, changeNote: null, expiresAt: null, readAt: null, readState: 'unread' as const }; }
function cache(scope = scopeA, title?: string) { return { scope, fetchedAt: savedAt, announcements: [card(title)], pendingReads: [{ announcementId: id(50), versionNo: 1 }] }; }
function feed(title = 'Current official closure') { return { ok: true, data: { asOf: '2026-10-03T08:00:00Z', announcements: [card(title)] } }; }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; }
function unmount() { for (const cell of h.cells) cell.cleanup?.(); h.cells = []; h.effects = []; h.cursor = 0; }
function render<T>(hook: () => T): T { h.cursor = 0; return hook(); }
async function settle<T>(hook: () => T): Promise<T> { let value = render(hook); for (let round = 0; round < 64; round++) { for (const effect of h.effects.splice(0)) effect(); await Promise.resolve(); value = render(hook); } return value; }
type Discard = (scope: Scope, isCurrent: () => boolean) => Promise<void>;
const discard = (cacheModule as unknown as Record<string, Discard>).discardAnnouncementCache;

beforeEach(async () => {
  unmount(); vi.resetAllMocks(); h.value = null; h.preview = false;
  h.get.mockImplementation(async () => h.value); h.set.mockImplementation(async (_key: string, value: string) => { h.value = value; }); h.remove.mockImplementation(async () => { h.value = null; });
  await cacheModule.clearAnnouncementCache(); h.remove.mockClear();
  h.identity = { kind: 'member', ...scopeA }; h.api = { post: h.post }; h.post.mockResolvedValue(feed());
  h.network.mockResolvedValue({ isConnected: true, isInternetReachable: true });
  h.staff.mockResolvedValue({ session: { supabase: { rpc: h.rpc }, userId: scopeA.userId, tenantId: scopeA.tenantId, staffId: id(7), role: 'gym_owner' } });
  vi.stubGlobal('fetch', h.fetch); vi.stubGlobal('window', new EventTarget()); vi.stubGlobal('navigator', { onLine: true });
});

describe('approved ANC actual server commands and registered route', () => {
  const draft = { kind: 'transactional', title: 'Sunday closure', body: 'The gym closes Sunday.', audience: 'all_members' };
  const request = (body: unknown) => new Request('https://gymloop.test/api/announcements', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const context = () => ({ params: Promise.resolve({ announcementId: id(50) }) });
  it.each(['throw', 'null scalar', 'wrong scalar'])('create %s after actual RPC attempt is an unknown outcome', async mode => {
    if (mode === 'throw') h.rpc.mockRejectedValue(new Error(secret));
    else h.rpc.mockResolvedValue({ data: mode === 'null scalar' ? null : { private: secret }, error: null });
    const response = await announcementCommand(request(draft), 'create'); const body = await response.json();
    expect(body.ok).toBe(false); expect(body.error.code).toBe('announcement_outcome_unknown'); expect(JSON.stringify(body)).not.toContain(secret); expect(h.rpc).toHaveBeenCalledTimes(1);
  });
  it.each([null, [], [{}], [{ published_at: 'bad', expires_at: null, audience_count: 1 }]].map(data => ({ data })))('publish malformed required row is unknown: $data', async ({ data }) => {
    h.rpc.mockResolvedValue({ data, error: null }); const response = await announcementCommand(request({}), 'publish', context());
    expect((await response.json()).error.code).toBe('announcement_outcome_unknown'); expect(h.rpc).toHaveBeenCalledTimes(1);
  });
  it('registered discard route preserves legitimate SQL void null success', async () => {
    h.rpc.mockResolvedValue({ data: null, error: null }); const req = request({}); const response = await discardRoute(req, context());
    expect(await response.json()).toEqual({ ok: true, data: { discarded: true } }); expect(h.rpc).toHaveBeenCalledTimes(1); expect(h.staff.mock.calls[0]).toContain(req);
  });
  it('registered route unexpected RPC throw is sanitized unknown, without replay', async () => {
    h.rpc.mockRejectedValue(new Error(secret)); const response = await discardRoute(request({}), context()); const body = await response.json();
    expect(body.error.code).toBe('announcement_outcome_unknown'); expect(JSON.stringify(body)).not.toContain(secret); expect(h.rpc).toHaveBeenCalledTimes(1);
  });
  it('definitive caller refusal stays definitive before any command', async () => {
    h.staff.mockResolvedValue({ failure: Response.json({ ok: false, error: { code: 'not_permitted', message: 'Permission denied.' } }, { status: 403 }) });
    const response = await announcementCommand(request(draft), 'create'); expect(response.status).toBe(403); expect((await response.json()).error.code).toBe('not_permitted'); expect(h.rpc).not.toHaveBeenCalled();
  });
});
afterEach(() => { unmount(); vi.unstubAllGlobals(); });

describe('approved ANC failure truth real copy and browser command hook', () => {
  it('adds the exact unknown-outcome copy while preserving definitive generic and specific refusals', () => {
    expect((ANNOUNCEMENT_REFUSAL_COPY as unknown as Record<string, string>).unknown_outcome).toBe(unknownCopy);
    expect(announcementRefusalMessage('unknown_outcome')).toBe(unknownCopy);
    expect(announcementRefusalMessage('not_draft')).toBe('This announcement is no longer a draft. Reload to see where it stands.');
    expect(announcementRefusalMessage('unrecognized_definitive_refusal')).toBe('The announcement could not be saved. Nothing was changed.');
  });
  it.each(['throw', 'bad JSON', 'missing envelope', 'malformed success'])('actual browser %s after submission uses unknown outcome and never replays', async failure => {
    if (failure === 'throw') h.fetch.mockRejectedValueOnce(new Error(secret));
    else h.fetch.mockResolvedValueOnce({ ok: true, json: failure === 'bad JSON' ? async () => { throw new Error(secret); } : async () => failure === 'missing envelope' ? null : { ok: true, data: null } });
    const initial = await settle(useAnnouncementCommand); expect(await initial.send('/api/announcements', { title: 'Closure' })).toBeNull();
    const result = await settle(useAnnouncementCommand); expect(result.error).toBe(unknownCopy); expect(String(result.error)).not.toContain(secret); expect(result.error).not.toContain('Nothing was changed');
    expect(h.fetch).toHaveBeenCalledTimes(1); window.dispatchEvent(new Event('online')); await settle(useAnnouncementCommand); expect(h.fetch).toHaveBeenCalledTimes(1); expect(h.refresh).not.toHaveBeenCalled();
  });
  it('maps actual announcement_outcome_unknown transport code to approved copy rather than upstream text', async () => {
    h.fetch.mockResolvedValue({ ok: false, json: async () => ({ ok: false, error: { code: 'announcement_outcome_unknown', message: secret } }) });
    const command = await settle(useAnnouncementCommand); expect(await command.send('/api/announcements', {})).toBeNull(); expect((await settle(useAnnouncementCommand)).error).toBe(unknownCopy);
  });
  it('keeps definitive version conflict distinct from an unknown result', async () => {
    h.fetch.mockResolvedValue({ ok: false, json: async () => ({ ok: false, error: { code: 'announcement_version_conflict', message: secret } }) });
    const command = await settle(useAnnouncementCommand); await command.send('/api/announcements', {}); const current = await settle(useAnnouncementCommand);
    expect(current.conflict).toBe(true); expect(current.error).toBe('Someone else changed this announcement while you were editing. Reload to see the latest version, then try again.');
  });
  it('preview and browser offline are known pre-command refusals with no transport', async () => {
    h.preview = true; const preview = await settle(useAnnouncementCommand); expect(await preview.send('/api/announcements', {})).toBeNull(); expect(h.fetch).not.toHaveBeenCalled(); unmount(); h.preview = false;
    (navigator as { onLine: boolean }).onLine = false; const offline = await settle(useAnnouncementCommand); expect(await offline.send('/api/announcements', {})).toBeNull(); expect(h.fetch).not.toHaveBeenCalled();
  });
});

describe('approved ANC actual native feed refusal and saved-copy truth', () => {
  it.each(['not_signed_in', 'not_permitted'])('current definitive %s drops refused cards/pending reads and kills retained acknowledgements', async code => {
    await cacheModule.saveAnnouncementCache(cache()); const old = await settle(useAnnouncements);
    h.post.mockResolvedValue({ ok: false, error: { code, message: secret } }); await old.reload(); const refused = await settle(useAnnouncements);
    expect(refused.cards).toEqual([]); expect(refused.error).toEqual(expect.any(String)); expect(refused.error).not.toContain(secret); expect(refused.error).not.toMatch(/offline|back online/i);
    expect(await cacheModule.loadAnnouncementCache(scopeA)).toBeNull(); h.post.mockClear();
    await old.markRead(id(50), 1); await refused.markRead(id(50), 1); expect(h.post).not.toHaveBeenCalled(); expect(await cacheModule.loadAnnouncementCache(scopeA)).toBeNull();
  });
  it.each(['server refusal', 'malformed feed', 'unknown network exception'])('current %s retains same-scope cards/time with refresh truth rather than an invented offline claim', async failure => {
    await cacheModule.saveAnnouncementCache({ ...cache(), pendingReads: [] });
    if (failure === 'server refusal') h.post.mockResolvedValue({ ok: false, error: { code: 'server_failure', message: secret } });
    if (failure === 'malformed feed') h.post.mockResolvedValue({ ok: true, data: { asOf: savedAt, announcements: [{ private: secret }] } });
    if (failure === 'unknown network exception') { h.post.mockRejectedValue(new Error(secret)); h.network.mockResolvedValue({ isConnected: null, isInternetReachable: null }); }
    const result = await settle(useAnnouncements); expect(result.cards).toEqual([card()]); expect(result.stale).toBe(true); expect(result.fetchedAt).toBe(savedAt);
    expect(result.error).toEqual(expect.any(String)); expect(result.error).not.toMatch(/offline|back online/i); expect(result.error).not.toContain(secret); expect(await cacheModule.loadAnnouncementCache(scopeB)).toBeNull();
  });
  it('only real disconnected or unreachable evidence permits offline wording', async () => {
    await cacheModule.saveAnnouncementCache({ ...cache(), pendingReads: [] }); h.post.mockRejectedValue(new Error(secret)); h.network.mockResolvedValue({ isConnected: true, isInternetReachable: false });
    const result = await settle(useAnnouncements); expect(result.cards).toEqual([card()]); expect(result.fetchedAt).toBe(savedAt); expect(result.stale).toBe(true); expect(String(result.error)).not.toContain(secret);
  });
  it('a first current refused read removes previously queued acknowledgements before a retained callback can send', async () => {
    await cacheModule.saveAnnouncementCache(cache()); h.post.mockResolvedValue({ ok: false, error: { code: 'not_signed_in', message: secret } });
    const refused = await settle(useAnnouncements); expect(refused.cards).toEqual([]); expect(await cacheModule.loadAnnouncementCache(scopeA)).toBeNull();
    h.post.mockClear(); await refused.markRead(id(50), 1); expect(h.post).not.toHaveBeenCalled();
  });
  it('late old-caller permission refusal cannot remove or revoke the newer complete scope cache', async () => {
    const late = deferred<unknown>(); h.post.mockReturnValueOnce(late.promise); await settle(useAnnouncements);
    h.identity = { kind: 'member', ...scopeB }; h.post.mockResolvedValue(feed('New caller official card')); await settle(useAnnouncements);
    const newerBefore = await cacheModule.loadAnnouncementCache(scopeB); expect(newerBefore?.announcements[0]?.title).toBe('New caller official card');
    late.resolve({ ok: false, error: { code: 'not_permitted', message: secret } }); const current = await settle(useAnnouncements);
    expect(current.cards[0]?.title).toBe('New caller official card'); expect(await cacheModule.loadAnnouncementCache(scopeB)).toEqual(newerBefore);
    await cacheModule.saveAnnouncementCache({ ...cache(scopeB, 'New caller subsequent save'), pendingReads: [] }); expect((await cacheModule.loadAnnouncementCache(scopeB))?.announcements[0]?.title).toBe('New caller subsequent save');
  });
});

describe('approved ANC real exact-scope serialized cache discard', () => {
  it('current scoped discard removes both cards and queued versions', async () => { await cacheModule.saveAnnouncementCache(cache()); await discard(scopeA, () => true); expect(await cacheModule.loadAnnouncementCache(scopeA)).toBeNull(); });
  it.each(['tenantId', 'userId', 'memberId'] as const)('refusal for a mismatched %s cannot delete current persisted scope', async dimension => {
    await cacheModule.saveAnnouncementCache(cache(scopeB)); const wrong = { ...scopeB, [dimension]: scopeA[dimension] }; const original = h.value;
    await discard(wrong, () => true); expect(h.value).toBe(original); expect(await cacheModule.loadAnnouncementCache(scopeB)).not.toBeNull(); expect(h.remove).not.toHaveBeenCalled();
  });
  it('a revoked discard is inert and does not globally revoke a newer save', async () => {
    await cacheModule.saveAnnouncementCache(cache()); await discard(scopeA, () => false); expect(await cacheModule.loadAnnouncementCache(scopeA)).not.toBeNull();
    await cacheModule.saveAnnouncementCache(cache(scopeB)); expect(await cacheModule.loadAnnouncementCache(scopeB)).not.toBeNull();
  });
  it('revocation while storage read waits prevents delete and leaves a later serialized new-scope save alive', async () => {
    await cacheModule.saveAnnouncementCache(cache()); const entered = deferred<void>(); const read = deferred<string | null>(); const oldDisk = h.value;
    h.get.mockImplementationOnce(() => { entered.resolve(); return read.promise; }); let current = true;
    const removing = discard(scopeA, () => current); await entered.promise; current = false; const saving = cacheModule.saveAnnouncementCache(cache(scopeB));
    read.resolve(oldDisk); await Promise.all([removing, saving]); expect(h.remove).not.toHaveBeenCalled(); expect((await cacheModule.loadAnnouncementCache(scopeB))?.scope).toEqual(scopeB);
  });
  it('an earlier in-flight old-scope save cannot resurrect refused cache after its serialized discard', async () => {
    const entered = deferred<void>(); const release = deferred<void>();
    h.set.mockImplementationOnce(async (_key: string, value: string) => { entered.resolve(); await release.promise; h.value = value; });
    const saving = cacheModule.saveAnnouncementCache(cache()); await entered.promise; const removing = discard(scopeA, () => true); release.resolve(); await Promise.all([saving, removing]);
    expect(await cacheModule.loadAnnouncementCache(scopeA)).toBeNull();
  });
});
