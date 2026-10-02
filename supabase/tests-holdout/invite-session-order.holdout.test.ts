// Independent native latest-session/claims and sign-out privacy contract.
// Actual provider, resolver and sign-out; only public native/auth/storage I/O mocked.
import { createRequire } from 'node:module';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const webRequire = createRequire(new URL('../../apps/web/package.json', import.meta.url));
const React = webRequire('react');
const h = vi.hoisted(() => ({
  client: null as any, observed: null as any, listener: null as any,
  initial: null as any, claimReplies: new Map<string, any>(), store: new Map<string, string>(),
  read: vi.fn(), write: vi.fn(), remove: vi.fn(), authoritativeSignOut: vi.fn(),
  effects: [] as (() => any)[], slots: new Map<string, any[]>(), contexts: new Map<any, any>(),
  current: '', index: 0, dirty: false,
}));
vi.mock('react', async () => {
  const actual = await vi.importActual<any>('react');
  const useState = (initial: any) => {
    const slots = h.slots.get(h.current) ?? []; h.slots.set(h.current, slots);
    const index = h.index++; if (!(index in slots)) slots[index] = typeof initial === 'function' ? initial() : initial;
    return [slots[index], (next: any) => {
      const value = typeof next === 'function' ? next(slots[index]) : next;
      if (!Object.is(value, slots[index])) { slots[index] = value; h.dirty = true; }
    }];
  };
  const useEffect = (effect: () => any, deps?: any[]) => {
    const slots = h.slots.get(h.current) ?? []; h.slots.set(h.current, slots);
    const index = h.index++; const previous = slots[index];
    if (!deps || !previous || deps.some((value, at) => !Object.is(value, previous[at]))) {
      slots[index] = deps; h.effects.push(effect);
    }
  };
  const useRef = (value: any) => useState(() => ({ current: value }))[0];
  const useContext = (context: any) => h.contexts.get(context) ?? context._currentValue;
  const useMemo = (factory: () => any, deps?: any[]) => {
    const slots = h.slots.get(h.current) ?? []; h.slots.set(h.current, slots);
    const index = h.index++; const previous = slots[index];
    if (!previous || !deps || deps.some((value, at) => !Object.is(value, previous.deps?.[at]))) {
      slots[index] = { deps, value: factory() };
    }
    return slots[index].value;
  };
  const useCallback = (callback: any, deps?: any[]) => useMemo(() => callback, deps);
  return { ...actual, useState, useEffect, useLayoutEffect: useEffect, useRef, useContext,
    useMemo, useCallback,
    default: { ...actual, useState, useEffect, useLayoutEffect: useEffect, useRef, useContext, useMemo, useCallback } };
});
vi.mock('@supabase/supabase-js', async () => ({ ...(await vi.importActual<any>('@supabase/supabase-js')), createClient: () => h.client }));
vi.mock('expo-secure-store', () => ({ getItemAsync: h.read, setItemAsync: h.write, deleteItemAsync: h.remove }));
vi.mock('expo-web-browser', () => ({ maybeCompleteAuthSession: vi.fn(), openAuthSessionAsync: vi.fn() }));
vi.mock('expo-font', () => ({ useFonts: () => [true, null], loadAsync: async () => undefined, isLoaded: () => true }));
vi.mock('expo-splash-screen', () => ({ preventAutoHideAsync: async () => undefined, hideAsync: async () => undefined }));
vi.mock('@expo-google-fonts/archivo', () => ({
  Archivo_400Regular: 'Archivo400', Archivo_500Medium: 'Archivo500', Archivo_600SemiBold: 'Archivo600', Archivo_700Bold: 'Archivo700',
  useFonts: () => [true, null],
}));
vi.mock('../../apps/mobile/assets/fonts/ArchivoExtraCondensed-ExtraBold.ttf', () => ({ default: 'IndependentExtraCondensedExtraBold' }));
vi.mock('../../apps/mobile/assets/fonts/ArchivoExtraCondensed-Bold.ttf', () => ({ default: 'IndependentExtraCondensedBold' }));
vi.mock('expo-network', () => ({
  getNetworkStateAsync: async () => ({ isConnected: true, isInternetReachable: true }),
  addNetworkStateListener: () => ({ remove: vi.fn() }),
  useNetworkState: () => ({ isConnected: true, isInternetReachable: true }),
}));
vi.mock('react-native', () => ({
  Platform: { OS: 'android', select: (options: any) => options.android ?? options.default },
  AppState: { currentState: 'active', addEventListener: () => ({ remove: vi.fn() }) },
  Appearance: { getColorScheme: () => 'dark', addChangeListener: () => ({ remove: vi.fn() }) },
  useColorScheme: () => 'dark', View: 'section', Text: 'span', Image: 'img', StatusBar: 'statusbar',
  Linking: { createURL: (path: string) => `fitcruxx://${path}` },
  StyleSheet: { create: (styles: any) => styles, flatten: (styles: any) => styles, hairlineWidth: 1 },
}));

const fixture = {
  userA: 'ac111111-1111-4111-8111-111111111111', userB: 'bd222222-2222-4222-8222-222222222222',
  tenantA: 'ce333333-3333-4333-8333-333333333333', tenantB: 'df444444-4444-4444-8444-444444444444',
  memberA: 'ea555555-5555-4555-8555-555555555555', memberB: 'fb666666-6666-4666-8666-666666666666',
  identityKey: 'gymloop.authenticated-identity',
};
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => { resolve = done; });
  return { promise, resolve };
}
function session(which: 'A' | 'B') {
  return { access_token: `controlled-token-${which}`, refresh_token: `controlled-refresh-${which}`, token_type: 'bearer', expires_in: 3600,
    user: { id: which === 'A' ? fixture.userA : fixture.userB, aud: 'authenticated', role: 'authenticated',
      email: `viewer-${which}@holdout.example`, app_metadata: {}, user_metadata: {}, created_at: '2026-10-02T00:00:00Z' } };
}
function verifiedClaims(which: 'A' | 'B') {
  return { data: { claims: { role: 'authenticated', sub: which === 'A' ? fixture.userA : fixture.userB,
    app_role: 'member', tenant_id: which === 'A' ? fixture.tenantA : fixture.tenantB,
    member_id: which === 'A' ? fixture.memberA : fixture.memberB } }, error: null };
}
function fresh(which: 'A' | 'B') {
  return { kind: 'member', userId: which === 'A' ? fixture.userA : fixture.userB,
    tenantId: which === 'A' ? fixture.tenantA : fixture.tenantB, memberId: which === 'A' ? fixture.memberA : fixture.memberB };
}
function render(value: any, key = 'root'): any {
  if (value == null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map((child, index) => render(child, `${key}/${index}`));
  const type = value.type;
  if (typeof type === 'function') {
    const oldKey = h.current; const oldIndex = h.index;
    h.current = key; h.index = 0; const output = type(value.props);
    h.current = oldKey; h.index = oldIndex;
    return render(output, `${key}/render`);
  }
  // React 19 context Provider may be the context itself, or a provider wrapper.
  if (type && (type.$$typeof === Symbol.for('react.context') || type.$$typeof === Symbol.for('react.provider'))) {
    h.contexts.set(type._context ?? type, value.props.value);
  }
  return render(value.props?.children, `${key}/children`);
}
async function mountProvider() {
  const { MobileProvider, useMobile } = await import('../../apps/mobile/lib/mobile-context');
  function Observer() { h.observed = useMobile(); return null; }
  const tree = React.createElement(MobileProvider, null, React.createElement(Observer));
  const flush = async () => {
    for (let round = 0; round < 12; round++) {
      h.dirty = false; render(tree);
      for (const effect of h.effects.splice(0)) effect();
      for (let step = 0; step < 12; step++) await Promise.resolve();
      if (!h.dirty && h.effects.length === 0) break;
    }
  };
  await flush(); return { flush };
}
function newestMember(which: 'A' | 'B') {
  expect(h.observed.ready).toBe(true);
  expect(h.observed.identity).toEqual(fresh(which));
  expect(h.observed.session.user.id).toBe(which === 'A' ? fixture.userA : fixture.userB);
}
function noResurrectedIdentity() {
  expect(h.observed.identity.kind).not.toBe('member');
  expect(h.observed.session).toBeNull();
  expect(h.store.has(fixture.identityKey)).toBe(false);
}

beforeEach(() => {
  vi.stubEnv('EXPO_PUBLIC_SUPABASE_URL', 'https://ordered-session.supabase.co');
  vi.stubEnv('EXPO_PUBLIC_SUPABASE_ANON_KEY', 'public-ordered-session-key');
  vi.stubEnv('EXPO_PUBLIC_API_BASE_URL', 'https://ordered-session.holdout.example');
  h.observed = null; h.listener = null; h.initial = deferred<any>(); h.claimReplies.clear();
  h.store.clear(); h.slots.clear(); h.contexts.clear(); h.effects = []; h.current = ''; h.index = 0; h.dirty = false;
  h.read.mockReset().mockImplementation(async (key: string) => h.store.get(key) ?? null);
  h.write.mockReset().mockImplementation(async (key: string, value: string) => { h.store.set(key, value); });
  h.remove.mockReset().mockImplementation(async (key: string) => { h.store.delete(key); });
  h.authoritativeSignOut.mockReset().mockResolvedValue({ error: null });
  h.client = { auth: {
    getSession: vi.fn(() => h.initial.promise),
    getClaims: vi.fn(async (token: string) => h.claimReplies.get(token)?.promise ?? verifiedClaims(token.endsWith('B') ? 'B' : 'A')),
    onAuthStateChange: (listener: any) => { h.listener = listener; return { data: { subscription: { unsubscribe: vi.fn() } } }; },
    signOut: h.authoritativeSignOut,
    startAutoRefresh: vi.fn(), stopAutoRefresh: vi.fn(),
  } };
});
afterEach(() => vi.unstubAllEnvs());

describe('native provider applies only the latest authoritative session resolution', () => {
  it('late initial getSession cannot overwrite a newer signed-in member event', async () => {
    const provider = await mountProvider();
    expect(h.listener).toBeTypeOf('function');
    h.listener('SIGNED_IN', session('B')); await provider.flush(); newestMember('B');
    h.initial.resolve({ data: { session: session('A') }, error: null });
    await provider.flush(); newestMember('B');
    const cached = h.store.get(fixture.identityKey);
    if (cached) expect(JSON.parse(cached)).toEqual(fresh('B'));
  });
  it('older in-flight claims cannot overwrite newer auth session or identity cache', async () => {
    const older = deferred<any>(); h.claimReplies.set('controlled-token-A', older);
    const provider = await mountProvider();
    h.initial.resolve({ data: { session: session('A') }, error: null }); await provider.flush();
    h.listener('SIGNED_IN', session('B')); await provider.flush(); newestMember('B');
    older.resolve(verifiedClaims('A')); await provider.flush(); newestMember('B');
    const cached = h.store.get(fixture.identityKey);
    if (cached) expect(JSON.parse(cached)).toEqual(fresh('B'));
  });
  it('a sign-out event defeats both late initial session and its obsolete verified identity', async () => {
    const provider = await mountProvider();
    h.listener('SIGNED_OUT', null); await provider.flush();
    h.initial.resolve({ data: { session: session('A') }, error: null });
    await provider.flush(); noResurrectedIdentity();
  });
  it('late claims after completed context sign-out cannot recreate user identity or cache', async () => {
    const older = deferred<any>(); h.claimReplies.set('controlled-token-A', older);
    const provider = await mountProvider();
    h.initial.resolve({ data: { session: null }, error: null }); await provider.flush();
    expect(h.observed.signOut).toBeTypeOf('function');
    h.listener('SIGNED_IN', session('A')); await provider.flush();
    await h.observed.signOut(); h.listener('SIGNED_OUT', null); await provider.flush();
    older.resolve(verifiedClaims('A')); await provider.flush(); noResurrectedIdentity();
    expect(h.authoritativeSignOut).toHaveBeenCalled();
  });
  it('an obsolete in-flight cache write cannot resurrect identity after sign-out completes', async () => {
    const releaseWrite = deferred<void>();
    h.write.mockImplementation(async (key: string, value: string) => {
      if (key === fixture.identityKey) await releaseWrite.promise;
      h.store.set(key, value);
    });
    const provider = await mountProvider();
    h.initial.resolve({ data: { session: null }, error: null }); await provider.flush();
    expect(h.observed.signOut).toBeTypeOf('function');
    h.listener('SIGNED_IN', session('A')); await provider.flush();
    expect(h.write.mock.calls.some(([key]: any[]) => key === fixture.identityKey)).toBe(true);
    const signOut = h.observed.signOut(); h.listener('SIGNED_OUT', null);
    // Resolve storage after sign-out starts. Completion must account for this older
    // operation even when the platform finishes the physical write late.
    releaseWrite.resolve(); await signOut; await provider.flush();
    noResurrectedIdentity(); expect(h.authoritativeSignOut).toHaveBeenCalled();
  });
});

describe('native authoritative sign-out survives optional identity cache deletion failure', () => {
  it('signOutMobile reaches auth.signOut even when identity-cache deletion rejects', async () => {
    h.remove.mockImplementation(async (key: string) => {
      if (key === fixture.identityKey) throw new Error('Optional identity cache cannot be deleted');
      h.store.delete(key);
    });
    const { signOutMobile } = await import('../../apps/mobile/lib/native-session');
    await expect(signOutMobile(h.client)).resolves.toBeUndefined();
    expect(h.authoritativeSignOut).toHaveBeenCalledOnce();
    // A failure in optional identity storage must not short-circuit all subsequent
    // SecureStore cleanup, including the independent queue ownership boundary.
    expect(h.remove.mock.calls.some(([key]: any[]) => key !== fixture.identityKey)).toBe(true);
  });
});
