import { beforeEach, describe, expect, it, vi } from 'vitest';
import { isValidElement, type ReactNode } from 'react';

const h = vi.hoisted(() => ({ slots: [] as unknown[], cursor: 0, effects: [] as Array<() => unknown>, callback: null as null | ((event: string, session: unknown) => void), initial: null as unknown, claims: new Map<string, { promise: Promise<unknown>; resolve: (value: unknown) => void }>(), cache: new Map<string, string>() }));
vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  return { ...actual,
    useState: (initial: unknown) => { const i = h.cursor++; if (!(i in h.slots)) h.slots[i] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return [h.slots[i], (next: unknown) => { h.slots[i] = typeof next === 'function' ? (next as (old: unknown) => unknown)(h.slots[i]) : next; }]; },
    useRef: (value: unknown) => { const i = h.cursor++; return h.slots[i] ?? (h.slots[i] = { current: value }); },
    useEffect: (effect: () => unknown, deps?: unknown[]) => { const i = h.cursor++; const old = h.slots[i] as unknown[] | undefined; if (!old || !deps || deps.some((v, index) => !Object.is(v, old[index]))) { h.slots[i] = deps; h.effects.push(effect); } },
    useMemo: (make: () => unknown, deps?: unknown[]) => {
      const i = h.cursor++;
      const old = h.slots[i] as { deps?: unknown[]; value: unknown } | undefined;
      if (!old || !deps || deps.some((value, index) => !Object.is(value, old.deps?.[index])) || deps.length !== old.deps?.length) {
        h.slots[i] = { deps, value: make() };
      }
      return (h.slots[i] as { value: unknown }).value;
    },
    useCallback: (fn: unknown, deps?: unknown[]) => {
      const i = h.cursor++;
      const old = h.slots[i] as { deps?: unknown[]; value: unknown } | undefined;
      if (!old || !deps || deps.some((value, index) => !Object.is(value, old.deps?.[index])) || deps.length !== old.deps?.length) {
        h.slots[i] = { deps, value: fn };
      }
      return (h.slots[i] as { value: unknown }).value;
    },
  };
});
vi.mock('expo-secure-store', () => ({ getItemAsync: async (key: string) => h.cache.get(key) ?? null, setItemAsync: async (key: string, value: string) => { h.cache.set(key, value); }, deleteItemAsync: async (key: string) => { h.cache.delete(key); } }));
vi.mock('expo-web-browser', () => ({ maybeCompleteAuthSession: () => undefined }));
vi.mock('expo-splash-screen', () => ({ preventAutoHideAsync: async () => undefined, hideAsync: async () => undefined }));
vi.mock('@expo-google-fonts/archivo', () => ({ useFonts: () => [true], Archivo_400Regular: 1, Archivo_500Medium: 1, Archivo_600SemiBold: 1, Archivo_700Bold: 1 }));
vi.mock('expo-font', () => ({ useFonts: () => [true] }));
vi.mock('../../assets/fonts/ArchivoExtraCondensed-ExtraBold.ttf', () => ({ default: 1 }));
vi.mock('../../assets/fonts/ArchivoExtraCondensed-Bold.ttf', () => ({ default: 1 }));
vi.mock('react-native', () => ({ StatusBar: () => null, useColorScheme: () => 'dark' }));
vi.mock('@gymloop/shared', async (original) => ({ ...await original<Record<string, unknown>>(), mobileClientEnv: () => ({ EXPO_PUBLIC_SUPABASE_URL: 'https://example.supabase.co', EXPO_PUBLIC_SUPABASE_ANON_KEY: 'public-key', EXPO_PUBLIC_API_BASE_URL: 'https://app.example' }) }));
vi.mock('../native-session', async (original) => ({ ...await original<Record<string, unknown>>(), createMobileSupabase: () => ({ auth: {
  getSession: async () => ({ data: { session: await h.initial }, error: null }),
  onAuthStateChange: (callback: typeof h.callback) => { h.callback = callback; return { data: { subscription: { unsubscribe: () => undefined } } }; },
  getClaims: async (token: string) => h.claims.get(token)!.promise,
  signOut: async () => ({ error: null }),
} }) }));

const USER = '11111111-1111-4111-8111-111111111111';
const TENANT = '22222222-2222-4222-8222-222222222222';
const OLD = '33333333-3333-4333-8333-333333333333';
const NEW = '44444444-4444-4444-8444-444444444444';
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>((done) => { resolve = done; }); return { promise, resolve }; }
function session(token: string) { return { access_token: token, user: { id: USER }, refresh_token: 'refresh', token_type: 'bearer', expires_in: 3600 }; }
function verified(memberId: string) { return { data: { claims: { role: 'authenticated', sub: USER, app_role: 'member', tenant_id: TENANT, member_id: memberId } }, error: null }; }
async function flush() { for (let i = 0; i < 12; i += 1) await Promise.resolve(); }
async function render() {
  const { MobileProvider } = await import('../mobile-context');
  h.cursor = 0;
  const tree = MobileProvider({ children: null });
  let value: Record<string, unknown> | undefined;
  const visit = (node: ReactNode) => { if (Array.isArray(node)) node.forEach(visit); else if (isValidElement<{ value?: Record<string, unknown>; children?: ReactNode }>(node)) { if (node.props.value && 'identity' in node.props.value) value = node.props.value; visit(node.props.children); } };
  visit(tree);
  const effects = h.effects.splice(0); effects.forEach((effect) => effect());
  await flush();
  return value!;
}
beforeEach(() => { h.slots = []; h.cursor = 0; h.effects = []; h.callback = null; h.initial = null; h.claims.clear(); h.cache.clear(); });

describe('HARD-011 / INV-022 native provider keeps the latest authoritative auth event', () => {
  it('older in-flight claims cannot overwrite a refreshed member or persist its obsolete cache', async () => {
    h.claims.set('old', deferred()); h.claims.set('new', deferred());
    await render(); h.callback!('SIGNED_IN', session('old')); await flush();
    h.callback!('TOKEN_REFRESHED', session('new')); await flush();
    h.claims.get('new')!.resolve(verified(NEW)); await flush();
    expect((await render()).identity).toMatchObject({ kind: 'member', memberId: NEW });
    h.claims.get('old')!.resolve(verified(OLD)); await flush();
    expect((await render()).identity).toMatchObject({ kind: 'member', memberId: NEW });
    expect(h.cache.get('gymloop.authenticated-identity') ?? '').not.toContain(OLD);
  });
  it('sign-out invalidates pending claims and prevents obsolete identity cache resurrection', async () => {
    h.claims.set('old', deferred()); await render();
    h.callback!('SIGNED_IN', session('old')); await flush();
    h.callback!('SIGNED_OUT', null); await flush();
    h.claims.get('old')!.resolve(verified(OLD)); await flush();
    const value = await render(); expect(value.session).toBeNull(); expect(value.identity).toMatchObject({ kind: 'unlinked' });
    expect(h.cache.get('gymloop.authenticated-identity') ?? '').not.toContain(OLD);
  });
  it.each(['TOKEN_REFRESHED', 'SIGNED_OUT'])('delayed initial getSession cannot supersede newer %s', async (event) => {
    const initial = deferred<unknown>(); h.initial = initial.promise;
    h.claims.set('old', deferred()); h.claims.set('new', deferred());
    await render(); h.callback!(event, event === 'SIGNED_OUT' ? null : session('new')); await flush();
    if (event !== 'SIGNED_OUT') { h.claims.get('new')!.resolve(verified(NEW)); await flush(); }
    initial.resolve(session('old')); await flush(); h.claims.get('old')!.resolve(verified(OLD)); await flush();
    const value = await render();
    if (event === 'SIGNED_OUT') { expect(value.session).toBeNull(); expect(value.identity).toMatchObject({ kind: 'unlinked' }); }
    else { expect(value.session).toMatchObject({ access_token: 'new' }); expect(value.identity).toMatchObject({ kind: 'member', memberId: NEW }); }
    expect(h.cache.get('gymloop.authenticated-identity') ?? '').not.toContain(OLD);
  });
});


