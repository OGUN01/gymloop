import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { isValidElement, type ReactNode } from 'react';

const h = vi.hoisted(() => ({ slots: [] as unknown[], cursor: 0, effects: [] as Array<() => unknown>, appListeners: new Set<(value: string) => void>(), queries: [] as Array<{ table: string; column: string; tenant: string }>, replies: [] as Array<Promise<unknown> | (() => Promise<unknown>)>, deletes: [] as string[], rejectVocabularyDelete: false, authSignOuts: 0, queueClears: 0, callback: null as null | ((event: string, session: unknown) => void), initial: null as unknown, claims: new Map<string, { promise: Promise<unknown>; resolve: (value: unknown) => void }>(), cache: new Map<string, string>() }));
vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  return { ...actual,
    useState: (initial: unknown) => { const i = h.cursor++; if (!(i in h.slots)) h.slots[i] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return [h.slots[i], (next: unknown) => { h.slots[i] = typeof next === 'function' ? (next as (old: unknown) => unknown)(h.slots[i]) : next; }]; },
    useRef: (value: unknown) => { const i = h.cursor++; return h.slots[i] ?? (h.slots[i] = { current: value }); },
    useEffect: (effect: () => unknown, deps?: unknown[]) => {
      const i = h.cursor++; const old = h.slots[i] as { deps?: unknown[]; cleanup?: unknown } | undefined;
      if (!old || !deps || deps.length !== old.deps?.length || deps.some((value, index) => !Object.is(value, old.deps?.[index]))) {
        const entry = { deps, cleanup: undefined as unknown }; h.slots[i] = entry;
        h.effects.push(() => { if (typeof old?.cleanup === 'function') old.cleanup(); entry.cleanup = effect(); });
      }
    },
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
vi.mock('expo-secure-store', () => ({ getItemAsync: async (key: string) => h.cache.get(key) ?? null, setItemAsync: async (key: string, value: string) => { h.cache.set(key, value); }, deleteItemAsync: async (key: string) => { h.deletes.push(key); if (h.rejectVocabularyDelete && key === 'gymloop.business-type') throw new Error('optional vocabulary storage unavailable'); h.cache.delete(key); } }));
vi.mock('../offline-check-in', async (original) => ({ ...await original<Record<string, unknown>>(), clearOfflineCheckIns: async () => { h.queueClears += 1; } }));
vi.mock('expo-web-browser', () => ({ maybeCompleteAuthSession: () => undefined }));
vi.mock('expo-splash-screen', () => ({ preventAutoHideAsync: async () => undefined, hideAsync: async () => undefined }));
vi.mock('@expo-google-fonts/archivo', () => ({ useFonts: () => [true], Archivo_400Regular: 1, Archivo_500Medium: 1, Archivo_600SemiBold: 1, Archivo_700Bold: 1 }));
vi.mock('expo-font', () => ({ useFonts: () => [true] }));
vi.mock('../../assets/fonts/ArchivoExtraCondensed-ExtraBold.ttf', () => ({ default: 1 }));
vi.mock('../../assets/fonts/ArchivoExtraCondensed-Bold.ttf', () => ({ default: 1 }));
vi.mock('react-native', () => ({ StatusBar: () => null, useColorScheme: () => 'dark', AppState: { currentState: 'active', addEventListener: (_event: string, listener: (value: string) => void) => { h.appListeners.add(listener); return { remove: () => h.appListeners.delete(listener) }; } } }));
vi.mock('@gymloop/shared', async (original) => ({ ...await original<Record<string, unknown>>(), mobileClientEnv: () => ({ EXPO_PUBLIC_SUPABASE_URL: 'https://example.supabase.co', EXPO_PUBLIC_SUPABASE_ANON_KEY: 'public-key', EXPO_PUBLIC_API_BASE_URL: 'https://app.example' }) }));
vi.mock('../native-session', async (original) => ({ ...await original<Record<string, unknown>>(), createMobileSupabase: () => ({ from: (table: string) => { const query = { table, column: '', tenant: '' }; return { select: (column: string) => { query.column = column; return { eq: (_key: string, tenant: string) => { query.tenant = tenant; return { maybeSingle: () => { h.queries.push(query); const reply = h.replies.shift(); return typeof reply === 'function' ? reply() : reply ?? Promise.resolve({ data: null, error: null }); } }; } }; } }; }, auth: {
  getSession: async () => ({ data: { session: await h.initial }, error: null }),
  onAuthStateChange: (callback: typeof h.callback) => { h.callback = callback; return { data: { subscription: { unsubscribe: () => { if (h.callback === callback) h.callback = null; } } } }; },
  getClaims: async (token: string) => h.claims.get(token)!.promise,
  signOut: async () => { h.authSignOuts += 1; return { error: null }; },
} }) }));

const USER = '11111111-1111-4111-8111-111111111111';
const TENANT = '22222222-2222-4222-8222-222222222222';
const OLD = '33333333-3333-4333-8333-333333333333';
const NEW = '44444444-4444-4444-8444-444444444444';
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>((done) => { resolve = done; }); return { promise, resolve }; }
function session(token: string) { return { access_token: token, user: { id: USER }, refresh_token: 'refresh', token_type: 'bearer', expires_in: 3600 }; }
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
beforeEach(() => { h.slots = []; h.cursor = 0; h.effects = []; h.callback = null; h.initial = null; h.claims.clear(); h.cache.clear(); h.appListeners.clear(); h.queries = []; h.replies = []; h.deletes = []; h.rejectVocabularyDelete = false; h.authSignOuts = 0; h.queueClears = 0; });
// The manual React host must unmount each provider before discarding its hook
// slots. Resetting counters alone leaves the previous lifecycle mounted.
// Auth unsubscribe mirrors the documented subscription host, not source logic.
afterEach(async () => {
  for (const slot of h.slots) {
    if (typeof slot !== 'object' || slot === null || !('cleanup' in slot)) continue;
    const cleanup = (slot as { cleanup?: unknown }).cleanup;
    if (typeof cleanup === 'function') await cleanup();
  }
  await flush();
  expect(h.appListeners.size).toBe(0);
  expect(h.callback).toBeNull();
});


// BIZ-011: execute the provider's auth, foreground and encrypted-storage effects.
// The transport is caller-session-only; no source inspection or real network.
const KEY = 'gymloop.business-type';
async function settle() { let value = await render(); for (let pass = 0; pass < 5; pass += 1) value = await render(); return value; }
async function start(kind: 'member' | 'staff' = 'member', tenant = TENANT) {
  h.initial = session('live'); const claims = deferred<unknown>(); h.claims.set('live', claims);
  claims.resolve({ data: { claims: { role: 'authenticated', sub: USER, app_role: kind === 'member' ? 'member' : 'front_desk', tenant_id: tenant, ...(kind === 'member' ? { member_id: OLD } : { staff_id: OLD }) } }, error: null });
  return settle();
}
const fetched = (type: string) => Promise.resolve({ data: { business_type: type }, error: null });
const fail = () => Promise.resolve({ data: null, error: { message: 'offline' } });
function foreground(value: string) { h.appListeners.forEach((listener) => listener(value)); }

describe('BIZ-011 native provider lifecycle', () => {
  it.each(['member', 'staff'] as const)('%s sign-out still clears commands and reaches Auth when vocabulary deletion rejects', async (kind) => {
    h.replies.push(fetched('dance')); const signedIn = await start(kind); h.rejectVocabularyDelete = true;
    let failure: unknown;
    try { await (signedIn.signOut as () => Promise<void>)(); } catch (error) { failure = error; }
    expect.soft(h.deletes).toContain(KEY);
    expect.soft(h.queueClears).toBe(1); expect.soft(h.authSignOuts).toBe(1);
    expect.soft((await settle()).businessType).toBeNull();
    expect(failure).toBeUndefined();
  });
  it.each(['member', 'staff'] as const)('%s reads its own organization and persists the fetched nouns', async (kind) => {
    h.replies.push(fetched('dance')); const value = await start(kind);
    expect(h.queries).toEqual([{ table: 'organizations', column: 'business_type', tenant: TENANT }]);
    expect(value.businessType).toBe('dance'); expect(value.nouns).toMatchObject({ place: 'academy', member: 'student', members: 'students', trainer: 'instructor' });
    expect(JSON.parse(h.cache.get(KEY)!)).toEqual({ t: TENANT, b: 'dance' });
  });
  it('hydrates a tenant-matching offline cold start without flipping to gym', async () => {
    h.cache.set(KEY, JSON.stringify({ t: TENANT, b: 'dance' })); h.replies.push(fail());
    const value = await start(); expect(value.businessType).toBe('dance'); expect(value.nouns).toMatchObject({ place: 'academy', members: 'students' });
    expect(JSON.parse(h.cache.get(KEY)!)).toEqual({ t: TENANT, b: 'dance' });
  });
  it("never hydrates another tenant's vocabulary", async () => {
    h.cache.set(KEY, JSON.stringify({ t: NEW, b: 'dance' })); h.replies.push(fail());
    const value = await start(); expect(value.businessType).toBeNull(); expect(value.nouns).toMatchObject({ place: 'gym', member: 'member' });
  });
  it('refreshes on each active transition; background does not fetch', async () => {
    h.replies.push(fetched('dance')); await start(); expect(h.appListeners.size).toBeGreaterThan(0);
    foreground('background'); await settle(); expect(h.queries).toHaveLength(1);
    h.replies.push(fetched('yoga')); foreground('active'); const yoga = await settle();
    expect(h.queries).toHaveLength(2); expect(yoga.businessType).toBe('yoga'); expect(yoga.nouns).toMatchObject({ place: 'studio', members: 'members' });
    foreground('inactive'); h.replies.push(fetched('martial_arts')); foreground('active');
    const academy = await settle(); expect(h.queries).toHaveLength(3); expect(academy.businessType).toBe('martial_arts');
    expect(JSON.parse(h.cache.get(KEY)!)).toEqual({ t: TENANT, b: 'martial_arts' });
  });
  it.each(['error', 'throw'] as const)('foreground %s keeps known words without a visible error', async (failure) => {
    h.replies.push(fetched('dance')); await start();
    h.replies.push(failure === 'error' ? fail() : () => Promise.reject(new Error('offline'))); foreground('active');
    const value = await settle(); expect(value.businessType).toBe('dance'); expect(value.nouns).toMatchObject({ place: 'academy' });
    expect(JSON.parse(h.cache.get(KEY)!)).toEqual({ t: TENANT, b: 'dance' });
  });
  it('SIGN_OUT clears vocabulary and deletes its encrypted cache', async () => {
    h.replies.push(fetched('dance')); await start(); h.callback!('SIGNED_OUT', null);
    const value = await settle(); expect(value.businessType).toBeNull(); expect(value.nouns).toMatchObject({ place: 'gym' });
    expect(h.deletes).toContain(KEY); expect(h.cache.has(KEY)).toBe(false);
    foreground('active'); await settle(); expect(h.queries).toHaveLength(1);
  });
  it('explicit signOut clears nouns and encrypted storage too', async () => {
    h.replies.push(fetched('dance')); const signedIn = await start();
    await (signedIn.signOut as () => Promise<void>)(); const value = await settle();
    expect(value.businessType).toBeNull(); expect(h.cache.has(KEY)).toBe(false); expect(h.deletes).toContain(KEY);
  });
  it('a tenantless identity clears vocabulary and stops organization reads', async () => {
    h.replies.push(fetched('dance')); await start();
    const claims = deferred<unknown>(); h.claims.set('platform', claims);
    claims.resolve({ data: { claims: { role: 'authenticated', sub: USER, app_role: 'super_admin' } }, error: null });
    h.callback!('TOKEN_REFRESHED', session('platform')); const value = await settle();
    expect(value.businessType).toBeNull(); expect(value.nouns).toMatchObject({ place: 'gym' }); expect(h.cache.has(KEY)).toBe(false);
    foreground('active'); await settle(); expect(h.queries).toHaveLength(1);
  });
  it('a pending read cannot restore signed-out vocabulary or storage', async () => {
    h.replies.push(fetched('dance')); await start();
    const pending = deferred<unknown>(); h.replies.push(pending.promise); foreground('active'); await settle();
    h.callback!('SIGNED_OUT', null); await settle(); pending.resolve({ data: { business_type: 'yoga' }, error: null });
    const value = await settle(); expect(value.businessType).toBeNull(); expect(h.cache.has(KEY)).toBe(false);
  });
  it('switching tenants clears old words and rejects the old tenant’s delayed read', async () => {
    h.replies.push(fetched('dance')); await start();
    const pending = deferred<unknown>(); h.replies.push(pending.promise); foreground('active'); await settle();
    const nextClaims = deferred<unknown>(); h.claims.set('next-tenant', nextClaims);
    nextClaims.resolve({ data: { claims: { role: 'authenticated', sub: USER, app_role: 'member', tenant_id: NEW, member_id: OLD } }, error: null });
    h.replies.push(fail()); h.callback!('TOKEN_REFRESHED', session('next-tenant'));
    const switched = await settle(); expect(switched.identity).toMatchObject({ kind: 'member', tenantId: NEW });
    expect(switched.businessType).toBeNull(); expect(switched.nouns).toMatchObject({ place: 'gym' });
    const persistedBeforeOldResponse = h.cache.get(KEY);
    pending.resolve({ data: { business_type: 'yoga' }, error: null }); const settled = await settle();
    expect(settled.businessType).toBeNull(); expect(h.cache.get(KEY)).toBe(persistedBeforeOldResponse);
    expect(h.queries.at(-1)?.tenant).toBe(NEW);
  });
});
