import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { businessNouns, UI_TOKENS } from '@gymloop/shared';
import type { MemberTraining } from '@gymloop/shared';
import type { Database } from '../../packages/db/types/database';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { ApiClient } from '../../packages/api-client/src/index';

// Independent deferred-media suite: actual adapter and actual TrainingSection.
// Neither shared readMemberTraining nor native loadTraining is replaced.
const seam = vi.hoisted(() => ({ value: {} as Record<string, unknown>, network: vi.fn(),
  cells: [] as unknown[], index: 0, effects: [] as (() => void)[], cleanups: [] as (() => void)[] }));
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => seam.value }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: seam.network, addNetworkStateListener: () => ({ remove: () => undefined }) }));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: vi.fn() }), router: { push: vi.fn() } }));
vi.mock('react', async original => {
  const real = await original<typeof import('../../apps/mobile/node_modules/@types/react/index')>();
  return { ...real,
    useState: (initial: unknown) => { const i = seam.index++; if (!(i in seam.cells)) seam.cells[i] = typeof initial === 'function' ? (initial as () => unknown)() : initial;
      return [seam.cells[i], (next: unknown) => { seam.cells[i] = typeof next === 'function' ? (next as (old: unknown) => unknown)(seam.cells[i]) : next; }]; },
    useRef: (initial: unknown) => { const i = seam.index++; if (!(i in seam.cells)) seam.cells[i] = { current: initial }; return seam.cells[i]; },
    useEffect: (effect: () => void | (() => void), deps?: unknown[]) => {
      const i = seam.index++; const old = seam.cells[i] as { deps?: unknown[]; cleanup?: () => void } | undefined;
      if (!old || !deps || deps.some((value, j) => value !== old.deps?.[j])) {
        const slot: { deps?: unknown[]; cleanup?: () => void } = deps ? { deps } : {}; seam.cells[i] = slot;
        seam.effects.push(() => { old?.cleanup?.(); const cleanup = effect(); if (cleanup) { slot.cleanup = cleanup; seam.cleanups.push(cleanup); } });
      }
    }, useMemo: (fn: () => unknown) => fn(), useCallback: (fn: unknown) => fn,
  };
});
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', Image: 'Image', ScrollView: 'ScrollView',
  StyleSheet: { create: (value: unknown) => value, hairlineWidth: 1 }, Platform: { OS: 'android' }, ActivityIndicator: 'ActivityIndicator' }));
vi.mock('../../apps/mobile/components/ui', () => ({ Status: 'Status', ActionButton: 'ActionButton', Row: 'Row', Sheet: 'Sheet',
  SheetHeader: 'SheetHeader', EmptyState: 'EmptyState', ErrorRetry: 'ErrorRetry', LoadingState: 'LoadingState',
  LedgerSection: 'LedgerSection', StateMessage: 'StateMessage', Body: 'Body' }));

type TrainerRow = Database['public']['Functions']['read_member_trainers']['Returns'][number];
const first: TrainerRow = { trainer_key: 'c8177c51-c831-46dd-a6ec-887209dd96f3', display_name: 'First listed coach',
  qualification: 'Coach certificate', bio: 'Safe coaching', specialities: ['Strength'], branch_name: 'East',
  image_asset_id: 'a8177c51-c831-46dd-a6ec-887209dd96f1', is_profile_listed: true };
const second: TrainerRow = { ...first, trainer_key: 'd8177c51-c831-46dd-a6ec-887209dd96f4',
  image_asset_id: 'b8177c51-c831-46dd-a6ec-887209dd96f2', display_name: 'Second listed coach' };
const identity = { kind: 'member', userId: 'e8177c51-c831-46dd-a6ec-887209dd96f5',
  tenantId: 'f8177c51-c831-46dd-a6ec-887209dd96f6', memberId: '08177c51-c831-46dd-a6ec-887209dd96f7' };
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; }
async function flush() { for (let i = 0; i < 12; i++) await Promise.resolve(); }
function boundaries() {
  const trainers = deferred<{ data: TrainerRow[]; error: null }>();
  let trainersStarted = false;
  const rpc = vi.fn((name: string) => {
    if (name === 'read_member_trainers' && !trainersStarted) { trainersStarted = true; return trainers.promise; }
    return Promise.resolve({ data: [], error: null });
  });
  const client = { rpc } as unknown as SupabaseClient<Database>;
  const post = vi.fn().mockImplementation((_path: string, body: { assetId: string }) => Promise.resolve({ ok: true, data: { imageUrl: `https://display.example/${body.assetId}` } }));
  const api = { post } as unknown as ApiClient;
  return { trainers, rpc, client, post, api };
}
beforeEach(() => { vi.clearAllMocks(); seam.cells = []; seam.index = 0; seam.effects = []; seam.cleanups = [];
  seam.network.mockResolvedValue({ isConnected: true, isInternetReachable: true }); });
afterEach(() => { seam.cleanups.splice(0).forEach(cleanup => cleanup()); vi.restoreAllMocks(); });

describe('independent actual native read adapter deferred MEDIA boundary', () => {
  it.each(['false', 'throw'] as const)('revoked projection continuation %s starts no image request', async mode => {
    const boundary = boundaries(); let current = true;
    const predicate = () => { if (!current && mode === 'throw') throw new Error('private obsolete lifetime'); return current; };
    const { loadTraining } = await import('../../apps/mobile/lib/training');
    const pending: Promise<MemberTraining> = Reflect.apply(loadTraining, undefined, [boundary.client, boundary.api, predicate]); await flush();
    current = false; boundary.trainers.resolve({ data: [first, second], error: null });
    const result = await pending;
    expect(boundary.post).not.toHaveBeenCalled(); expect(result.trainers.data?.map((row: { imageUrl: string | null }) => row.imageUrl)).toEqual([null, null]);
  });
  it('current predicate sends exact public asset IDs and preserves public metadata only', async () => {
    const boundary = boundaries(); const { loadTraining } = await import('../../apps/mobile/lib/training');
    const pending: Promise<MemberTraining> = Reflect.apply(loadTraining, undefined, [boundary.client, boundary.api, () => true]);
    boundary.trainers.resolve({ data: [first, second], error: null }); const result = await pending;
    expect(boundary.post.mock.calls).toEqual([
      ['/api/member/media-url', { assetId: first.image_asset_id }], ['/api/member/media-url', { assetId: second.image_asset_id }],
    ]);
    expect(result.trainers.data).toEqual([first, second].map(row => ({ trainerKey: row.trainer_key, displayName: row.display_name,
      qualification: row.qualification, bio: row.bio, specialities: row.specialities, branchName: row.branch_name,
      isProfileListed: row.is_profile_listed, imageUrl: `https://display.example/${row.image_asset_id}` })));
  });
  it('first synchronous media invocation revokes later invocations without canceling the started request', async () => {
    const boundary = boundaries(); let current = true; const started = deferred<unknown>();
    boundary.post.mockImplementationOnce(() => { current = false; return started.promise; });
    const { loadTraining } = await import('../../apps/mobile/lib/training');
    const pending: Promise<MemberTraining> = Reflect.apply(loadTraining, undefined, [boundary.client, boundary.api, () => current]);
    boundary.trainers.resolve({ data: [first, second], error: null }); await flush();
    expect(boundary.post).toHaveBeenCalledOnce(); expect(boundary.post).toHaveBeenCalledWith('/api/member/media-url', { assetId: first.image_asset_id });
    started.resolve({ ok: true, data: { imageUrl: 'https://display.example/already-started' } }); await pending;
    expect(boundary.post).toHaveBeenCalledOnce();
  });
  it('omitted lease predicate preserves existing caller adapter behavior', async () => {
    const boundary = boundaries(); const { loadTraining } = await import('../../apps/mobile/lib/training');
    const pending = loadTraining(boundary.client, boundary.api); boundary.trainers.resolve({ data: [first], error: null }); await pending;
    expect(boundary.post).toHaveBeenCalledWith('/api/member/media-url', { assetId: first.image_asset_id });
  });
});

describe('independent actual TrainingSection passes permanent deferred read predicate', () => {
  it.each(['caller', 'api', 'supabase', 'ready', 'unmount'] as const)('%s replacement permanently refuses original pending media even after A B A', async reason => {
    const boundary = boundaries(); const replacement = boundaries();
    seam.value = { identity, supabase: boundary.client, api: boundary.api, ready: true, nouns: businessNouns('gym'),
      palette: UI_TOKENS.colors.light, businessType: 'gym', session: null, appearance: 'light' };
    const actualTraining = await import('../../apps/mobile/lib/training');
    const observed = vi.spyOn(actualTraining, 'loadTraining');
    const { TrainingSection } = await import('../../apps/mobile/components/training-section');
    const render = () => { seam.index = 0; const tree = TrainingSection(); seam.effects.splice(0).forEach(effect => effect()); return tree; };
    render(); await flush(); expect(observed).toHaveBeenCalled();
    const originalPredicate = Reflect.get(observed.mock.calls[0]!, '2') as (() => boolean) | undefined;
    expect(originalPredicate).toBeTypeOf('function'); expect(originalPredicate!()).toBe(true);
    const originalValue = seam.value;
    if (reason === 'unmount') seam.cleanups.splice(0).forEach(cleanup => cleanup());
    else {
      seam.value = { ...seam.value, ...(reason === 'caller' ? { identity: { ...identity, memberId: '18177c51-c831-46dd-a6ec-887209dd96f8' } }
        : reason === 'api' ? { api: replacement.api } : reason === 'supabase' ? { supabase: replacement.client } : { ready: false }) };
      render(); await flush(); expect(originalPredicate!()).toBe(false);
      seam.value = originalValue; render(); await flush();
    }
    expect(originalPredicate!()).toBe(false);
    boundary.trainers.resolve({ data: [first, second], error: null }); replacement.trainers.resolve({ data: [], error: null });
    await flush();
    // Fresh reads return empty image metadata; only the original pending projection
    // has these assets, so zero posts distinguishes obsolete work from current work.
    await observed.mock.results[0]?.value;
    expect(boundary.post).not.toHaveBeenCalled();
    if (reason !== 'unmount') {
      expect(originalPredicate!()).toBe(false);
      const originalResult = await observed.mock.results[0]?.value;
      expect(originalResult.trainers.data?.map((row: { imageUrl: string | null }) => row.imageUrl)).toEqual([null, null]);
    }
    expect(replacement.post).not.toHaveBeenCalled();
  });
});
