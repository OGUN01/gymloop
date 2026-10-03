import { describe, expect, it, vi } from 'vitest';
import { createApiClient, type ApiFetch } from '@gymloop/api-client';
import type { Database } from '@gymloop/db';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadTraining } from '../training';
import type { ReactNode } from 'react';

type Trainer = Database['public']['Functions']['read_member_trainers']['Returns'][number];
const assets = ['10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002'];
const trainers: Trainer[] = assets.map((asset, index) => ({
  trainer_key: `20000000-0000-4000-8000-00000000000${index + 1}`,
  display_name: `Listed trainer ${index}`, qualification: 'Certified', bio: 'Strength coaching',
  branch_name: 'Main', specialities: ['Strength'], image_asset_id: asset, is_profile_listed: true,
}));

function projections() {
  const pending: Array<{ name: string; complete: () => void }> = [];
  const rpc = vi.fn((name: string) => new Promise(resolve => {
    pending.push({ name, complete: () => resolve({ data: name === 'read_member_trainers' ? trainers : [], error: null }) });
  }));
  return { client: { rpc } as unknown as SupabaseClient<Database>, rpc, pending };
}

function media(onInvoke?: () => void, fails = false) {
  const fetch = vi.fn<ApiFetch>(async (_path, init) => {
    onInvoke?.();
    const { assetId } = JSON.parse(init.body) as { assetId: string };
    return { json: async () => fails
      ? { ok: false, error: { code: 'MEDIA_UNAVAILABLE', message: 'Unavailable' } }
      : { ok: true, data: { imageUrl: `https://media.example/${assetId}` } } };
  });
  return { fetch, api: createApiClient({ baseUrl: 'https://gym.example', accessToken: async () => 'current-access', fetch }) };
}

// The optional predicate is the frozen public addition; the pre-build signature
// accepts fewer arguments and must still execute for a behavioral red result.
const read = loadTraining as (client: SupabaseClient<Database>, api?: ReturnType<typeof createApiClient>, predicate?: () => boolean) => ReturnType<typeof loadTraining>;

describe('native deferred trainer media permanent lease', () => {
  it.each(['revoked', 'throwing'] as const)('awaits all five actual projections and refuses a %s continuation', async refusal => {
    const source = projections();
    const boundary = media();
    let current = true;
    const result = read(source.client, boundary.api, () => {
      if (!current && refusal === 'throwing') throw new Error('Retired lease');
      return current;
    });
    expect(source.rpc).toHaveBeenCalledTimes(5);
    expect(boundary.fetch).not.toHaveBeenCalled();
    const last = source.pending.at(-1);
    for (const projection of source.pending.slice(0, -1)) projection.complete();
    await Promise.resolve();
    expect(boundary.fetch).not.toHaveBeenCalled();
    current = false;
    last?.complete();
    const loaded = await result;
    expect(boundary.fetch).not.toHaveBeenCalled();
    expect(loaded.trainers.data?.map(trainer => trainer.imageUrl)).toEqual([null, null]);
  });

  it('a current lease posts only the exact listed assets through the API', async () => {
    const source = projections();
    const boundary = media();
    const result = read(source.client, boundary.api, () => true);
    source.pending.forEach(projection => projection.complete());
    const loaded = await result;
    expect(boundary.fetch.mock.calls.map(([path, init]) => ({ path, body: JSON.parse(init.body) as unknown }))).toEqual(
      assets.map(assetId => ({ path: 'https://gym.example/api/member/media-url', body: { assetId } })),
    );
    expect(loaded.trainers.data?.map(trainer => trainer.imageUrl)).toEqual(assets.map(asset => `https://media.example/${asset}`));
  });

  it('checks immediately before each post: synchronous first-post revocation prevents later posts', async () => {
    const source = projections();
    let current = true;
    const post = vi.fn(() => {
      current = false;
      return Promise.resolve({ ok: true as const, data: { imageUrl: 'https://media.example/started-before-revocation' } });
    });
    const api = { post, checkIn: vi.fn() } as unknown as ReturnType<typeof createApiClient>;
    const result = read(source.client, api, () => current);
    source.pending.forEach(projection => projection.complete());
    const loaded = await result;
    expect(post).toHaveBeenCalledTimes(1);
    expect(post).toHaveBeenCalledWith('/api/member/media-url', { assetId: assets[0] });
    expect(loaded.trainers.data?.[0]?.imageUrl).toBe('https://media.example/started-before-revocation');
    expect(loaded.trainers.data?.[1]?.imageUrl).toBeNull();
  });

  it('an unsuccessful media response preserves successful trainer reads with placeholders', async () => {
    const source = projections();
    const boundary = media(undefined, true);
    const result = read(source.client, boundary.api, () => true);
    source.pending.forEach(projection => projection.complete());
    const loaded = await result;
    expect(boundary.fetch).toHaveBeenCalledTimes(2);
    expect(loaded.trainers.error).toBeNull();
    expect(loaded.trainers.data?.map(trainer => trainer.imageUrl)).toEqual([null, null]);
  });

  it('preserves the existing omitted-predicate read interface', async () => {
    const source = projections();
    const boundary = media();
    const result = loadTraining(source.client, boundary.api);
    source.pending.forEach(projection => projection.complete());
    const loaded = await result;
    expect(boundary.fetch).toHaveBeenCalledTimes(2);
    expect(loaded.trainers.data?.map(trainer => trainer.imageUrl)).toEqual(assets.map(asset => `https://media.example/${asset}`));
  });
});

describe('TrainingSection passes a permanent read continuation', () => {
  it.each(['caller', 'api', 'client', 'readiness', 'unmount'] as const)('retires old predicates permanently on %s, including A → B → A', async replacement => {
    const cells: unknown[] = [];
    const effects: Array<{ deps: readonly unknown[] | undefined; cleanup: (() => void) | undefined }> = [];
    const pendingEffects: Array<() => void> = [];
    let position = 0;
    let effectPosition = 0;
    const predicates: Array<(() => boolean) | undefined> = [];
    const clientA = projections().client;
    const clientB = projections().client;
    const apiA = media().api;
    const apiB = media().api;
    const memberA = { kind: 'member', userId: '30000000-0000-4000-8000-000000000001', tenantId: '40000000-0000-4000-8000-000000000001', memberId: '50000000-0000-4000-8000-000000000001' };
    const memberB = { ...memberA, memberId: '50000000-0000-4000-8000-000000000002' };
    const context = {
      identity: memberA, ready: true, api: apiA, supabase: clientA,
      nouns: { business: 'gym', businesses: 'gyms', member: 'member', members: 'members', trainer: 'trainer', trainers: 'trainers', session: 'session', sessions: 'sessions' },
      businessType: 'gym', palette: {}, session: null,
    };
    vi.doMock('react', async importOriginal => {
      const actual = await importOriginal<typeof import('react')>();
      const memo = (compute: () => unknown, deps?: readonly unknown[]) => {
        const cell = position++;
        const previous = cells[cell] as { value: unknown; deps: readonly unknown[] | undefined } | undefined;
        if (previous && deps && previous.deps && deps.length === previous.deps.length && deps.every((value, index) => Object.is(value, previous.deps?.[index]))) return previous.value;
        const next = { value: compute(), deps };
        cells[cell] = next;
        return next.value;
      };
      return {
        ...actual,
        useState: (initial: unknown) => {
          const cell = position++;
          if (!(cell in cells)) cells[cell] = typeof initial === 'function' ? (initial as () => unknown)() : initial;
          return [cells[cell], (next: unknown) => { cells[cell] = typeof next === 'function' ? (next as (previous: unknown) => unknown)(cells[cell]) : next; }];
        },
        useRef: (initial: unknown) => {
          const cell = position++;
          if (!(cell in cells)) cells[cell] = { current: initial };
          return cells[cell];
        },
        useEffect: (effect: () => (() => void) | void, deps?: readonly unknown[]) => {
          const cell = effectPosition++;
          const previous = effects[cell];
          if (previous && deps && previous.deps && deps.length === previous.deps.length && deps.every((value, index) => Object.is(value, previous.deps?.[index]))) return;
          pendingEffects.push(() => { previous?.cleanup?.(); effects[cell] = { deps, cleanup: effect() ?? undefined }; });
        },
        useCallback: (callback: unknown, deps?: readonly unknown[]) => memo(() => callback, deps),
        useMemo: memo,
      };
    });
    vi.doMock('../mobile-context', () => ({ useMobile: () => context }));
    vi.doMock('../training', async importOriginal => ({
      ...await importOriginal<typeof import('../training')>(),
      loadTraining: (_client: unknown, _api: unknown, predicate?: () => boolean) => {
        predicates.push(predicate);
        return new Promise(() => undefined);
      },
    }));
    vi.doMock('expo-network', () => ({
      getNetworkStateAsync: async () => ({ isConnected: true, isInternetReachable: true }),
      addNetworkStateListener: () => ({ remove: () => undefined }),
    }));
    vi.doMock('expo-router', () => ({ useRouter: () => ({ push: vi.fn(), replace: vi.fn(), back: vi.fn() }) }));
    vi.doMock('react-native', () => ({
      View: 'View', Text: 'Text', Pressable: 'Pressable', ScrollView: 'ScrollView', Image: 'Image', ActivityIndicator: 'ActivityIndicator',
      StyleSheet: { create: (styles: unknown) => styles }, Platform: { OS: 'android' },
    }));
    vi.doMock('lucide-react-native', () => new Proxy({}, { get: () => () => null }));
    vi.doMock('../../components/ui', () => Object.fromEntries(
      ['Body', 'Status', 'ActionButton', 'Row', 'Sheet', 'SheetHeader', 'EmptyState', 'ErrorRetry', 'LoadingState', 'LedgerSection', 'StateMessage']
        .map(name => [name, (props: { children?: ReactNode }) => props.children ?? null]),
    ));
    const { TrainingSection } = await import('../../components/training-section');
    const render = async () => {
      position = 0;
      effectPosition = 0;
      const tree: ReactNode = TrainingSection();
      expect(tree).toBeDefined();
      pendingEffects.splice(0).forEach(effect => effect());
      await Promise.resolve();
      await Promise.resolve();
    };
    try {
      await render();
      expect(predicates.length).toBeGreaterThan(0);
      const original = predicates[0];
      expect(original).toBeTypeOf('function');
      expect(original?.()).toBe(true);
      if (replacement === 'unmount') effects.forEach(effect => effect.cleanup?.());
      else {
        if (replacement === 'caller') context.identity = memberB;
        if (replacement === 'api') context.api = apiB;
        if (replacement === 'client') context.supabase = clientB;
        if (replacement === 'readiness') context.ready = false;
        await render();
      }
      expect(original?.()).toBe(false);
      if (replacement !== 'unmount') {
        context.identity = memberA;
        context.api = apiA;
        context.supabase = clientA;
        context.ready = true;
        await render();
        expect(original?.()).toBe(false);
        expect(predicates.every(predicate => typeof predicate === 'function')).toBe(true);
        expect(predicates.at(-1)?.()).toBe(true);
      }
    } finally {
      effects.forEach(effect => effect.cleanup?.());
      for (const module of ['react', '../mobile-context', '../training', 'expo-network', 'expo-router', 'react-native', 'lucide-react-native', '../../components/ui']) vi.doUnmock(module);
      vi.resetModules();
    }
  });
});

