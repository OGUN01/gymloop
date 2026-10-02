// Frozen INV-029/030 behavioral holdout, authored without implementation or other suites.
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { UI_TOKENS } from '@gymloop/shared';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const webRequire = createRequire(new URL('../../apps/web/package.json', import.meta.url));
const { createElement } = webRequire('react');

const io = vi.hoisted(() => ({
  token: 'R'.repeat(43), gym: 'Independent Recovery Gym', email: 'viewer@recovery.example',
  context: null as any, identity: null as any, client: null as any,
  stored: new Map<string, string>(), order: [] as string[], effects: [] as (() => any)[],
  slots: new Map<string, any[]>(), current: '', index: 0, changed: false,
  post: vi.fn(), fetch: vi.fn(), replace: vi.fn(), push: vi.fn(), oauth: vi.fn(),
  refresh: vi.fn(), signOut: vi.fn(), open: vi.fn(), digest: vi.fn(),
}));

// A deterministic hook renderer runs the real components and event handlers. Native styling
// primitives are hosts, and platform/network/auth I/O is mocked. No component names or tree
// positions are assumed by assertions; controls are found by their visible text.
vi.mock('react', async () => {
  const actual = await vi.importActual<any>('react');
  const useState = (initial: any) => {
    const key = io.current; const index = io.index++;
    const slots = io.slots.get(key) ?? []; io.slots.set(key, slots);
    if (!(index in slots)) slots[index] = typeof initial === 'function' ? initial() : initial;
    return [slots[index], (next: any) => {
      const value = typeof next === 'function' ? next(slots[index]) : next;
      if (!Object.is(value, slots[index])) { slots[index] = value; io.changed = true; }
    }];
  };
  const useEffect = (effect: () => any, deps?: any[]) => {
    const slots = io.slots.get(io.current) ?? []; io.slots.set(io.current, slots);
    const index = io.index++; const previous = slots[index];
    if (!deps || !previous || deps.some((value, at) => !Object.is(value, previous[at]))) {
      slots[index] = deps; io.effects.push(effect);
    }
  };
  const useRef = (value: any) => useState(() => ({ current: value }))[0];
  return { ...actual, useState, useEffect, useLayoutEffect: useEffect, useRef,
    useMemo: (fn: () => any) => fn(), useCallback: (fn: any) => fn,
    default: { ...actual, useState, useEffect, useLayoutEffect: useEffect, useRef } };
});
vi.mock('../../apps/mobile/lib/mobile-context.tsx', () => ({ useMobile: () => io.context }));
vi.mock('../../apps/mobile/components/ui.tsx', () => ({ FONT: {
  regular: 'Archivo_400Regular', medium: 'Archivo_500Medium', semibold: 'Archivo_600SemiBold',
  bold: 'Archivo_700Bold', display: 'ArchivoExtraCondensed_700Bold',
}, ...Object.fromEntries([
  'Screen', 'Eyebrow', 'Title', 'Body', 'Surface', 'ActionButton', 'Field', 'StateMessage', 'LoadingState',
].map(name => [name, name === 'ActionButton' ? 'button' : name === 'Field' ? 'input' : 'section'])) }));
vi.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ token: io.token }), useRouter: () => ({ replace: io.replace, push: io.push }),
  router: { replace: io.replace, push: io.push }, Link: 'a', Redirect: 'redirect',
}));
vi.mock('expo-secure-store', () => ({
  getItemAsync: async (key: string) => io.stored.get(key) ?? null,
  setItemAsync: async (key: string, value: string) => { io.order.push('save'); io.stored.set(key, value); },
  deleteItemAsync: async (key: string) => { io.stored.delete(key); },
}));
vi.mock('expo-crypto', () => ({ CryptoDigestAlgorithm: { SHA256: 'SHA-256' }, digestStringAsync: io.digest }));
vi.mock('expo-web-browser', () => ({
  maybeCompleteAuthSession: vi.fn(), openAuthSessionAsync: io.open, openBrowserAsync: io.open,
}));
vi.mock('expo-network', () => ({
  getNetworkStateAsync: async () => ({ isConnected: io.context.online, isInternetReachable: io.context.online }),
  useNetworkState: () => ({ isConnected: io.context.online, isInternetReachable: io.context.online }),
}));
vi.mock('react-native', () => ({
  View: 'section', Text: 'span', Pressable: 'button', TouchableOpacity: 'button', TextInput: 'input',
  ScrollView: 'section', ActivityIndicator: 'progress', Platform: { OS: 'android', select: (options: any) => options.android ?? options.default },
  StyleSheet: { create: (styles: any) => styles, flatten: (styles: any) => styles, hairlineWidth: 1 },
  Linking: { openURL: io.open, createURL: (path: string) => `fitcruxx://${path}` },
  AppState: { currentState: 'active', addEventListener: () => ({ remove: vi.fn() }) },
  useColorScheme: () => 'light', useWindowDimensions: () => ({ width: 400, height: 800, fontScale: 1 }),
}));
vi.mock('@supabase/supabase-js', async () => ({ ...(await vi.importActual<any>('@supabase/supabase-js')),
  createClient: () => io.client,
}));
vi.mock('../../apps/web/lib/supabase/server.ts', () => ({ createServerSupabase: async () => io.client }));
vi.mock('../../apps/web/lib/identity-session.ts', () => ({ readIdentity: async () => ({
  signedIn: true, authenticatedUser: true, identity: io.identity, supabase: io.client,
}) }));
vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: io.replace, push: io.push, refresh: io.refresh }),
  redirect: (url: string) => { io.replace(url); return null; },
}));
vi.mock('next/headers', () => ({ cookies: async () => ({
  get: (name: string) => name === 'fitcruxx_invite' ? { value: io.token } : undefined,
  getAll: () => [], set: vi.fn(),
}) }));

type Host = { type: any; props: any; children: any[] };
function expand(value: any, key = 'root'): any {
  if (value == null || typeof value === 'boolean') return null;
  if (Array.isArray(value)) return value.map((child, index) => expand(child, `${key}/${index}`));
  if (typeof value !== 'object') return value;
  if (typeof value.type === 'function') {
    const previous = io.current; const previousIndex = io.index;
    io.current = key; io.index = 0;
    const rendered = value.type(value.props);
    io.current = previous; io.index = previousIndex;
    return expand(rendered, `${key}/render`);
  }
  return { type: value.type, props: value.props ?? {}, children: [expand(value.props?.children, `${key}/children`)] };
}
function walk(tree: any): Host[] {
  if (tree == null || typeof tree !== 'object') return [];
  if (Array.isArray(tree)) return tree.flatMap(walk);
  return [tree, ...tree.children.flatMap(walk)];
}
function text(tree: any): string {
  if (tree == null) return '';
  if (typeof tree !== 'object') return String(tree);
  if (Array.isArray(tree)) return tree.map(text).join(' ');
  // Named labels are part of native primitive props, even when children are omitted.
  return [tree.props.label, tree.props.title, tree.props.message, ...tree.children.map(text)].filter(Boolean).join(' ');
}
async function mount(component: any, props: any = {}) {
  let tree: any;
  const flush = async () => {
    for (let round = 0; round < 12; round++) {
      io.changed = false; tree = expand(createElement(component, props));
      for (const effect of io.effects.splice(0)) effect();
      // Platform promises often include peek, secure storage and refresh in sequence.
      for (let step = 0; step < 8; step++) await Promise.resolve();
      if (!io.changed && io.effects.length === 0) break;
    }
    return tree;
  };
  await flush();
  return { tree: () => tree, text: () => text(tree), flush,
    press: async (label: RegExp) => {
      const control = walk(tree).find(node => label.test(text(node)) &&
        (typeof node.props.onPress === 'function' || typeof node.props.onClick === 'function'));
      expect(control, `action ${label} must be reachable`).toBeTruthy();
      await (control!.props.onPress ?? control!.props.onClick)(); await flush();
    },
  };
}
function privateView(tree: any) {
  const view = text(tree);
  for (const secret of ['SECRET_MEMBER_NAME', 'member-secret@elsewhere.example', '+919000009999', 'SECRET_OTHER_GYM']) expect(view).not.toContain(secret);
}
function ownRecovery(screen: Awaited<ReturnType<typeof mount>>) {
  expect(screen.text()).toContain(io.email);
  expect(screen.text()).toMatch(/different.*account|switch.*account/i);
  privateView(screen.tree());
}

beforeEach(() => {
  vi.stubEnv('WEB_APP_URL', 'https://recovery-trusted.holdout.example');
  vi.stubEnv('EXPO_PUBLIC_API_BASE_URL', 'https://recovery-trusted.holdout.example');
  vi.stubEnv('EXPO_PUBLIC_SUPABASE_URL', 'https://recovery.supabase.co');
  vi.stubEnv('EXPO_PUBLIC_SUPABASE_ANON_KEY', 'holdout-public-key');
  io.slots.clear(); io.effects = []; io.stored.clear(); io.order = []; io.changed = false;
  for (const spy of [io.post, io.fetch, io.replace, io.push, io.oauth, io.refresh, io.signOut, io.open, io.digest]) spy.mockReset();
  io.identity = { kind: 'unlinked', userId: 'd1111111-1111-4111-8111-111111111111' };
  io.oauth.mockImplementation(async () => { io.order.push('oauth'); return { data: { url: 'https://accounts.google.com/independent' }, error: null }; });
  io.open.mockResolvedValue({ type: 'cancel' });
  io.digest.mockImplementation(async (_algorithm: string, raw: string) => createHash('sha256').update(raw).digest('hex'));
  io.refresh.mockResolvedValue({ data: { session: { user: { email: io.email } } }, error: null });
  io.signOut.mockResolvedValue({ error: null });
  io.client = { rpc: vi.fn(async (name: string, args: any) => {
    expect(name).toBe('peek_member_invite');
    expect(args).toEqual({ p_token_hash: createHash('sha256').update(io.token).digest('hex') });
    return { data: [{ gym_name: io.gym }], error: null };
  }), auth: { signInWithOAuth: io.oauth, refreshSession: io.refresh, signOut: io.signOut,
    getUser: async () => ({ data: { user: { id: io.identity.userId, email: io.email } }, error: null }),
    getClaims: async () => ({ data: { claims: { sub: io.identity.userId } }, error: null }),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe: vi.fn() } } }),
  } };
  io.post.mockResolvedValue({ ok: true, data: { outcome: 'already_linked_here', gymName: io.gym } });
  io.fetch.mockResolvedValue(new Response(JSON.stringify({ ok: true, data: { outcome: 'already_linked_here', gymName: io.gym } }),
    { headers: { 'Content-Type': 'application/json' } }));
  vi.stubGlobal('fetch', io.fetch);
  vi.stubGlobal('window', { location: { replace: io.replace, assign: io.push } });
  io.context = { supabase: io.client, api: { post: io.post }, identity: io.identity,
    palette: UI_TOKENS.colors.dark,
    session: { user: { email: io.email } }, webOrigin: 'https://recovery-trusted.holdout.example',
    online: true, ready: true, status: 'ready', refresh: io.refresh, signOut: io.signOut,
    signInWithGoogle: async () => {
      const native = await import('../../apps/mobile/lib/native-session');
      return (native.signInWithGoogleMobile as any)(io.client);
    },
  };
});
afterEach(() => { vi.unstubAllEnvs(); vi.unstubAllGlobals(); });

describe('INV-029 real native invite landing', () => {
  it('peeks with local SHA256, places gym/notice/privacy before Google and saves before direct OAuth chooser', async () => {
    io.context.session = null; io.context.identity = { kind: 'none' };
    const { default: Page } = await import('../../apps/mobile/app/invite/[token]');
    const screen = await mount(Page);
    expect(io.digest).toHaveBeenCalledWith('SHA-256', io.token);
    expect(io.client.rpc).toHaveBeenCalled();
    const copy = screen.text();
    expect(copy).toContain(io.gym); expect(copy).toContain(`By linking, you let ${io.gym}`);
    expect(copy).toContain('your visits, payments and messages');
    const googleButtonAt = copy.search(/(?:continue|sign in) with Google/i);
    expect(googleButtonAt).toBeGreaterThanOrEqual(0);
    expect(copy.indexOf(io.gym)).toBeLessThan(googleButtonAt);
    expect(copy.indexOf('By linking')).toBeLessThan(googleButtonAt);
    expect(walk(screen.tree()).some(node => JSON.stringify(node.props).includes('https://recovery-trusted.holdout.example/privacy')
      || /privacy/i.test(text(node)) && typeof node.props.onPress === 'function')).toBe(true);
    expect(io.post).not.toHaveBeenCalled(); privateView(screen.tree());
    await screen.press(/continue.*Google|sign in.*Google/i);
    expect([...io.stored.values()]).toContain(io.token);
    expect(io.order.indexOf('save')).toBeLessThan(io.order.indexOf('oauth'));
    expect(io.oauth).toHaveBeenCalledWith(expect.objectContaining({ provider: 'google',
      options: expect.objectContaining({ queryParams: { prompt: 'select_account' } }) }));
    expect(io.push).not.toHaveBeenCalledWith('/sign-in');
  });
  it.each(['unavailable', 'connection'])('names %s peek failure honestly without member facts or auto-bind', async cause => {
    io.context.session = null;
    io.client.rpc.mockResolvedValue(cause === 'unavailable' ? { data: [], error: null } : { data: null, error: { message: 'connection refused' } });
    const { default: Page } = await import('../../apps/mobile/app/invite/[token]');
    const screen = await mount(Page);
    expect(screen.text()).toMatch(cause === 'unavailable' ? /invite.*(?:unavailable|can.t|expired|replaced)/i : /connection|connect|offline|try again|retry/i);
    expect(io.post).not.toHaveBeenCalled(); expect(io.oauth).not.toHaveBeenCalled(); privateView(screen.tree());
  });
});

describe('INV-030 actual web member reopen', () => {
  it('uses client POST for same-account replay and safely opens member home, never mutating during server render', async () => {
    io.identity = { kind: 'member', userId: 'd1111111-1111-4111-8111-111111111111',
      tenantId: 'e2222222-2222-4222-8222-222222222222', memberId: 'f3333333-3333-4333-8333-333333333333' };
    const { default: Page } = await import('../../apps/web/app/invite/[token]/page');
    const element = await Page({ params: Promise.resolve({ token: io.token }) });
    expect(io.client.rpc.mock.calls.every(([name]: any[]) => name === 'peek_member_invite')).toBe(true);
    expect(io.fetch).not.toHaveBeenCalled();
    const screen = await mount(() => element);
    expect(io.fetch).toHaveBeenCalledWith(expect.stringContaining('/api/member-invites/redeem'),
      expect.objectContaining({ method: 'POST' }));
    expect(io.replace.mock.calls.some(([path]: any[]) => {
      const home = new URL(String(path), 'https://recovery-trusted.holdout.example');
      return home.origin === 'https://recovery-trusted.holdout.example' && home.pathname === '/member';
    })).toBe(true);
    privateView(screen.tree());
  });
  it('other linked audience receives own-email account recovery without client binding', async () => {
    io.identity = { kind: 'staff', role: 'trainer', userId: 'd1111111-1111-4111-8111-111111111111',
      tenantId: 'e2222222-2222-4222-8222-222222222222', staffId: 'f3333333-3333-4333-8333-333333333333' };
    const { default: Page } = await import('../../apps/web/app/invite/[token]/page');
    const element = await Page({ params: Promise.resolve({ token: io.token }) });
    const screen = await mount(() => element);
    ownRecovery(screen); expect(io.fetch).not.toHaveBeenCalled();
  });
});

describe('INV-030 actual native member reopen and saved-invite recovery', () => {
  it('same-account already_linked_here uses live POST, fresh claims and member home', async () => {
    io.context.identity = { kind: 'member', userId: 'd1111111-1111-4111-8111-111111111111',
      tenantId: 'e2222222-2222-4222-8222-222222222222', memberId: 'f3333333-3333-4333-8333-333333333333' };
    const { default: Page } = await import('../../apps/mobile/app/invite/[token]');
    const screen = await mount(Page);
    expect(io.post).toHaveBeenCalledWith('/api/member-invites/redeem', { token: io.token });
    expect(io.refresh).toHaveBeenCalled();
    expect(io.replace.mock.calls.some(([path]: any[]) => /member/.test(String(path)))).toBe(true);
    privateView(screen.tree());
  });
  it.each(['account_already_linked', 'network'])('linked member %s refusal keeps token and provides own-email switch', async outcome => {
    io.context.identity = { kind: 'member', userId: 'd1111111-1111-4111-8111-111111111111',
      tenantId: 'e2222222-2222-4222-8222-222222222222', memberId: 'f3333333-3333-4333-8333-333333333333' };
    io.post.mockRejectedValue({ code: outcome, message: outcome === 'network' ? 'Cannot connect' : 'This account is already joined as a member and can\'t be linked again.' });
    const { default: Page } = await import('../../apps/mobile/app/invite/[token]');
    const screen = await mount(Page); ownRecovery(screen);
    expect(io.replace.mock.calls.some(([path]: any[]) => /member/.test(String(path)))).toBe(false);
    await screen.press(/different.*account|switch.*account/i);
    expect([...io.stored.values()]).toContain(io.token);
    expect(io.signOut).toHaveBeenCalled();
  });
  it('saved invite on not-linked names gym and privacy without automatic redemption', async () => {
    io.stored.set('gymloop.pending-invite', io.token);
    const { default: Page } = await import('../../apps/mobile/app/not-linked');
    const screen = await mount(Page);
    expect(screen.text()).toContain(io.gym); expect(screen.text()).toMatch(/privacy/i);
    expect(io.post).not.toHaveBeenCalled(); privateView(screen.tree());
  });
  it('offline replay never queues redemption or opens a falsely linked home', async () => {
    io.context.online = false;
    io.context.identity = { kind: 'member', userId: 'd1111111-1111-4111-8111-111111111111',
      tenantId: 'e2222222-2222-4222-8222-222222222222', memberId: 'f3333333-3333-4333-8333-333333333333' };
    io.post.mockRejectedValue({ code: 'network', message: 'Offline. Try again when connected.' });
    const { default: Page } = await import('../../apps/mobile/app/invite/[token]');
    const screen = await mount(Page);
    expect(screen.text()).toMatch(/offline|connect|retry|try again/i);
    expect([...io.stored.keys()].some(key => /queue|offline.*command|check.?in/i.test(key))).toBe(false);
    expect(io.replace.mock.calls.some(([path]: any[]) => /member/.test(String(path)))).toBe(false);
    expect(io.refresh).not.toHaveBeenCalled(); privateView(screen.tree());
  });
});
