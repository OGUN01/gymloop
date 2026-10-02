import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, isValidElement, type ReactElement, type ReactNode } from 'react';
import { UI_TOKENS } from '@gymloop/shared';

/** Owner-approved INV-029/030. Execute real native route/screens/effects with
 * native presentation and platform I/O replaced. Never inspect source strings.
 */
const { state } = vi.hoisted(() => ({ state: {
  identity: { kind: 'unlinked' } as Record<string, unknown>, signedIn: false,
  slots: [] as unknown[], cursor: 0, effects: [] as Array<() => unknown>,
  store: new Map<string, string>(), events: [] as string[], homes: [] as string[], urls: [] as string[],
  rpc: [] as Array<{ name: string; args: unknown }>, oauth: [] as unknown[],
  posts: [] as Array<{ path: string; body: unknown }>, outcome: 'already_linked_here',
  peek: [{ gym_name: 'Iron Box Fitness' }] as unknown[], peekFailure: false, network: false,
  refreshes: 0, signOuts: 0,
  brand: false,
  storageFailure: false, apiError: '', routeParams: {} as Record<string, string>,
} }));
const TOKEN = 'Q'.repeat(43);
// Independently computed SHA-256 of the fixed UTF-8 token, using .NET SHA256.
const TOKEN_HASH = '9cdc7469f022f9e7965d22eff1ab2c260adcd0c23b98d199c519762f3a0be959';
const KEY = 'gymloop.pending-invite';
const EMAIL = 'viewer.google@example.com';
const GYM = 'Iron Box Fitness';
const NOTICE = `By linking, you let ${GYM} connect this Google account (your name and email) to your membership record. FitCruxx processes it on ${GYM}'s behalf to show you your visits, payments and messages. Ask ${GYM} to unlink it at any time.`;
const REFUSALS: Record<string, string> = {
  invite_unavailable: "This invite can't be used. It may have expired or been replaced. Ask your gym to send a new one.",
  email_mismatch: "This invite wasn't sent to this Google account. Sign in with the email your gym has on file for you, or ask them to update it.",
  identity_unverified: "Sign in with Google to use this invite. This account wasn't created with a verified Google sign-in.",
  account_already_linked: "This account is already joined as a member and can't be linked again. Ask your gym to send the invite to a different email.",
  rate_limited: 'Too many attempts. Wait a few minutes, then try again.',
};
vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  const slot = (initial: unknown) => { const key = state.cursor++; if (!(key in state.slots)) state.slots[key] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return key; };
  return { ...actual,
    useState: (initial: unknown) => { const key = slot(initial); return [state.slots[key], (next: unknown) => { state.slots[key] = typeof next === 'function' ? (next as (old: unknown) => unknown)(state.slots[key]) : next; }]; },
    useRef: (initial: unknown) => state.slots[slot({ current: initial })],
    useEffect: (effect: () => unknown, deps?: unknown[]) => { const key = state.cursor++; const old = state.slots[key] as unknown[] | undefined; if (!old || !deps || deps.some((value, index) => !Object.is(value, old[index]))) { state.slots[key] = deps; state.effects.push(effect); } },
    useMemo: (make: () => unknown) => make(), useCallback: (callback: unknown) => callback,
    useId: () => 'native-invite', useTransition: () => [false, (run: () => unknown) => run()],
  };
});
const host = (name: string) => (props: Record<string, unknown>) => createElement(name, props, props.children as ReactNode);
vi.mock('react-native', () => ({
  View: host('view'), Text: host('text'), Pressable: host('button'), TextInput: host('input'), ScrollView: host('scroll'), Image: host('image'),
  StyleSheet: { create: (value: unknown) => value }, Platform: { OS: 'android', select: (value: Record<string, unknown>) => value.android },
  Linking: { openURL: async (url: string) => { state.urls.push(url); } },
}));
vi.mock('expo-router', () => ({
  useLocalSearchParams: () => state.routeParams, useGlobalSearchParams: () => state.routeParams,
  router: { replace: (path: unknown) => state.homes.push(typeof path === 'string' ? path : JSON.stringify(path)), push: (path: unknown) => state.homes.push(typeof path === 'string' ? path : JSON.stringify(path)) },
  useRouter: () => ({ replace: (path: unknown) => state.homes.push(typeof path === 'string' ? path : JSON.stringify(path)), push: (path: unknown) => state.homes.push(typeof path === 'string' ? path : JSON.stringify(path)) }),
  Link: host('link'), Redirect: (props: { href: string }) => { state.homes.push(props.href); return null; },
}));
vi.mock('expo-secure-store', () => ({
  getItemAsync: async (key: string) => { if (state.storageFailure) throw new Error('secure storage unavailable'); return state.store.get(key) ?? null; },
  setItemAsync: async (key: string, value: string) => { state.events.push('save'); state.store.set(key, value); },
  deleteItemAsync: async (key: string) => { state.store.delete(key); },
}));
vi.mock('expo-crypto', () => ({
  CryptoDigestAlgorithm: { SHA256: 'SHA-256' }, CryptoEncoding: { HEX: 'hex' },
  digestStringAsync: async (algorithm: unknown, value: string) => {
    expect(algorithm).toBe('SHA-256'); expect(value).toBe(TOKEN);
    state.events.push('hash'); return TOKEN_HASH;
  },
}));
vi.mock('expo-web-browser', () => ({
  maybeCompleteAuthSession: () => undefined,
  openBrowserAsync: async (url: string) => { state.urls.push(url); return { type: 'dismiss' }; },
  openAuthSessionAsync: async (url: string) => { state.events.push('browser'); state.urls.push(url); return { type: 'cancel' }; },
}));
vi.mock('react-native-svg', () => ({ default: host('svg'), Svg: host('svg'), Path: host('path'), G: host('g'), Circle: host('circle'), Rect: host('rect'), Defs: host('defs'), ClipPath: host('clipPath'), LinearGradient: host('linearGradient'), RadialGradient: host('radialGradient'), Stop: host('stop') }));
vi.mock('react-native-safe-area-context', () => ({
  SafeAreaView: host('safe-area'), SafeAreaProvider: host('safe-area-provider'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));
vi.mock('lucide-react-native', () => new Proxy({}, {
  get: (_target, name) => name === 'then' ? undefined : host('icon'),
  has: () => true,
}));
vi.mock('expo-haptics', () => ({ selectionAsync: async () => undefined, impactAsync: async () => undefined, notificationAsync: async () => undefined }));
vi.mock('../../components/ui', async (original) => {
  const actual = await original<Record<string, unknown>>();
  return { FONT: new Proxy({}, { get: () => 'test-font' }), ...Object.fromEntries([
  'Screen', 'Eyebrow', 'Title', 'Body', 'Surface', 'Field', 'LoadingState', 'StateMessage', 'ActionButton',
].map((name) => [name, (props: Record<string, unknown>) => state.brand && name === 'ActionButton'
  ? createElement(actual.ActionButton as never, props as never)
  : createElement(name === 'ActionButton' ? 'button' : name === 'Field' ? 'input' : 'view', props,
    [props.title, props.message, props.label, props.children].filter((value) => value !== undefined) as ReactNode)])) };
});
const supabase = {
  rpc: async (name: string, args: unknown) => { state.rpc.push({ name, args }); if (state.peekFailure) throw new Error('connection unavailable'); return { data: state.peek, error: null }; },
  from: () => { throw new Error('native invite must never read person records'); },
  auth: {
    getUser: async () => ({ data: { user: state.signedIn ? { id: 'u1', email: EMAIL } : null }, error: null }),
    refreshSession: async () => { state.refreshes += 1; state.events.push('refresh'); return { data: { session: {} }, error: null }; },
    signOut: async () => { state.signOuts += 1; state.events.push('signout'); return { error: null }; },
    exchangeCodeForSession: async () => ({ data: { session: { user: { id: 'u1', email: EMAIL } } }, error: null }),
    signInWithOAuth: async (options: unknown) => { state.events.push('oauth'); state.oauth.push(options); return { data: { url: 'https://google.example/chooser' }, error: null }; },
  },
};
const api = { post: async (path: string, body: unknown) => {
  state.posts.push({ path, body }); state.events.push('post'); if (state.network) throw new Error('offline');
  return state.apiError ? { ok: false, error: { code: state.apiError, message: 'The invite could not be checked. Try again.' } }
    : Object.hasOwn(REFUSALS, state.outcome) ? { ok: false, error: { code: state.outcome, message: REFUSALS[state.outcome] } }
    : { ok: true, data: { outcome: state.outcome, gymName: 'Forbidden other gym' } };
} };
vi.mock('../mobile-context', () => ({ useMobile: () => ({
  identity: state.identity, session: state.signedIn ? { user: { id: 'u1', email: EMAIL } } : null,
  loading: false, ready: true, supabase, api, webOrigin: 'https://app.example', palette: UI_TOKENS.colors.dark,
  signOut: async () => { state.signOuts += 1; state.events.push('signout'); },
  signInWithGoogle: async () => {
    const { signInWithGoogleMobile } = await import('../native-session');
    return signInWithGoogleMobile({ supabase: supabase as never, openBrowser: async () => ({ type: 'cancel' }) });
  },
}) }));
type Element = ReactElement<Record<string, unknown>>;
function expand(node: ReactNode): ReactNode {
  if (Array.isArray(node)) return node.map(expand);
  if (!isValidElement<Record<string, unknown>>(node)) return node;
  if (typeof node.type === 'function') return expand((node.type as (props: unknown) => ReactNode)(node.props));
  return createElement(node.type, node.props, expand(node.props.children as ReactNode));
}
function nodes(node: ReactNode): Element[] {
  if (Array.isArray(node)) return node.flatMap(nodes);
  if (!isValidElement<Record<string, unknown>>(node)) return [];
  return [node, ...nodes(node.props.children as ReactNode)];
}
function text(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(text).join(' ');
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (!isValidElement<Record<string, unknown>>(node)) return '';
  return text(node.props.children as ReactNode).replace(/\s+/g, ' ').trim();
}
async function screen(kind: 'landing' | 'saved' | 'callback' = 'landing') {
  const Screen = kind === 'landing' ? (await import('../../app/invite/[token]')).default : kind === 'saved' ? (await import('../../app/not-linked')).default : (await import('../../app/auth/callback')).default;
  const draw = () => { state.cursor = 0; return expand(createElement(Screen)); };
  let tree = draw();
  const settle = async () => {
    for (let pass = 0; pass < 6; pass += 1) { for (const effect of state.effects.splice(0)) await effect(); await new Promise((resolve) => setTimeout(resolve, 0)); tree = draw(); }
    return tree;
  };
  await settle();
  return { draw, settle, get tree() { return tree; } };
}
async function press(view: Awaited<ReturnType<typeof screen>>, label: RegExp) {
  const button = nodes(view.tree).find((node) => node.type === 'button' && label.test(text(node)));
  expect(button, `native action ${String(label)}`).toBeDefined();
  expect(button?.props.disabled).not.toBe(true);
  await (button?.props.onPress as () => unknown)(); await view.settle();
}
beforeEach(() => {
  state.identity = { kind: 'unlinked' }; state.signedIn = false; state.slots = []; state.cursor = 0; state.effects = [];
  state.store = new Map(); state.events = []; state.homes = []; state.urls = []; state.rpc = []; state.oauth = []; state.posts = [];
  state.outcome = 'already_linked_here'; state.peek = [{ gym_name: GYM }]; state.peekFailure = false; state.network = false; state.refreshes = 0; state.signOuts = 0;
  state.brand = false;
  state.storageFailure = false; state.apiError = ''; state.routeParams = { token: TOKEN };
});
describe('INV-029 native landing consent and direct Google', () => {
  it('INV-029 / INV-Q4 Google button renders the current official gradient G on an approved background with a 48dp target', async () => {
    state.brand = true;
    const view = await screen();
    const button = nodes(view.tree).find((node) => node.type === 'button' && /Continue with Google|Sign in with Google/i.test(text(node)));
    expect(button, 'the real rendered Google control').toBeDefined();
    // Official guidance fetched 2026-10-02 now requires the gradient super G:
    // https://developers.google.com/identity/branding-guidelines
    const content = nodes(button);
    const image = content.find((node) => node.type === 'image');
    expect(image, 'render the unmodified official gradient PNG').toBeDefined();
    const imageSource = image?.props.source as { uri?: string } | undefined;
    const uri = imageSource?.uri ?? '';
    if (uri.startsWith('data:image/png;base64,')) {
      // Browser-standard decoding/digest keeps Node types out of native tests.
      const platform = globalThis as unknown as {
        atob: (input: string) => string;
        crypto: { subtle: { digest: (algorithm: string, data: Uint8Array) => Promise<ArrayBuffer> } };
      };
      const bytes = Uint8Array.from(platform.atob(uri.slice('data:image/png;base64,'.length)), (character) => character.charCodeAt(0));
      const digest = await platform.crypto.subtle.digest('SHA-256', bytes);
      const hex = [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
      expect(hex).toBe('d1ce9c2af0b10a7333abc99bc706f9a6a199e5b65bf3e3009624f076b8638e6a');
    } else {
      expect(uri).toBe('https://developers.google.com/static/identity/images/g-logo.png');
    }
    const flatten = (value: unknown): Record<string, unknown> => Array.isArray(value)
      ? Object.assign({}, ...value.map(flatten)) : value && typeof value === 'object' ? value as Record<string, unknown> : {};
    const rawStyle = button?.props.style;
    const style = flatten(typeof rawStyle === 'function' ? rawStyle({ pressed: false }) : rawStyle);
    expect(Number(style.minHeight ?? style.height)).toBeGreaterThanOrEqual(48);
    const background = String(style.backgroundColor ?? '').toLowerCase();
    expect(background).toMatch(/^#[0-9a-f]{3}(?:[0-9a-f]{3})?$/);
    const fullHex = background.length === 4 ? `#${background.slice(1).split('').map((digit) => `${digit}${digit}`).join('')}` : background;
    expect(['#ffffff', '#131314', '#f2f2f2']).toContain(fullHex);
  });
  it('first peeks gym-only using expo-crypto SHA256, shows notice/privacy before Google, never redirects to sign-in', async () => {
    const view = await screen(); const visible = text(view.tree);
    expect(state.rpc).toEqual([{ name: 'peek_member_invite', args: { p_token_hash: TOKEN_HASH } }]);
    expect(JSON.stringify(state.rpc)).not.toContain(TOKEN); expect(state.events).toContain('hash');
    expect(visible).toContain(GYM); expect(visible).toContain(NOTICE);
    expect(visible.indexOf(NOTICE)).toBeLessThan(visible.indexOf('Continue with Google'));
    const privacy = nodes(view.tree).find((node) => node.props.href === 'https://app.example/privacy' || /privacy/i.test(text(node)) && typeof node.props.onPress === 'function');
    expect(privacy).toBeDefined();
    if (typeof privacy?.props.onPress === 'function') { await privacy.props.onPress(); expect(state.urls).toContain('https://app.example/privacy'); }
    expect(state.posts).toEqual([]); expect(state.homes).not.toContain('/sign-in');
    await press(view, /Continue with Google|Sign in with Google/i);
    expect(state.store.get(KEY)).toBe(TOKEN); expect(state.events.indexOf('save')).toBeLessThan(state.events.indexOf('oauth'));
    expect(state.oauth).toHaveLength(1);
    expect(state.oauth[0]).toMatchObject({ provider: 'google', options: { queryParams: { prompt: 'select_account' } } });
    expect(JSON.stringify(state.oauth)).not.toContain(TOKEN); expect(state.homes).not.toContain('/sign-in');
  });
  it('distinguishes unavailable invite from connection failure with honest recovery', async () => {
    state.peek = []; const missing = text((await screen()).tree);
    state.slots = []; state.effects = []; state.peekFailure = true;
    const failure = text((await screen()).tree);
    expect(missing).toMatch(/invite.*(used|unavailable)|new.*invite/i);
    expect(failure).toMatch(/connection|internet|offline|try again/i); expect(failure).not.toBe(missing);
    expect(state.posts).toEqual([]); expect(failure).not.toContain(TOKEN);
  });
  it('saved invite after sign-in names the gym and full notice before linking', async () => {
    state.signedIn = true; state.store.set(KEY, TOKEN);
    const view = await screen('saved');
    expect(text(view.tree)).toContain(GYM); expect(text(view.tree)).toContain(NOTICE);
    expect(nodes(view.tree).some((node) => node.props.href === 'https://app.example/privacy' || /privacy/i.test(text(node)) && typeof node.props.onPress === 'function')).toBe(true);
    expect(state.posts).toEqual([]);
  });
});
describe('INV-030 native replay and account recovery', () => {
  beforeEach(() => { state.signedIn = true; state.identity = { kind: 'member', userId: 'u1', tenantId: 't1', memberId: 'm1' }; });
  it('member replay POSTs through live API and refreshes before opening home only for already_linked_here', async () => {
    await screen();
    expect(state.posts).toEqual([{ path: '/api/member-invites/redeem', body: { token: TOKEN } }]);
    expect(state.refreshes).toBe(1); expect(state.events.indexOf('post')).toBeLessThan(state.events.indexOf('refresh'));
    expect(state.homes).toContain('/(member)');
  });
  it.each(['linked', 'invite_unavailable', 'account_already_linked', 'unknown_outcome'])('%s is not replay success: email, one-tap switch and retained token', async (outcome) => {
    state.outcome = outcome;
    const view = await screen();
    expect(state.homes).not.toContain('/(member)'); expect(state.refreshes).toBe(0);
    expect(text(view.tree)).toContain(EMAIL); expect(text(view.tree)).not.toContain('Forbidden other gym');
    await press(view, /different.*account/i); expect(state.signOuts).toBeGreaterThan(0); expect(state.store.get(KEY)).toBe(TOKEN);
  });
  it('offline replay never queues or claims success and preserves account recovery', async () => {
    state.network = true; const view = await screen();
    expect(text(view.tree)).toMatch(/try again|offline|connection/i); expect(text(view.tree)).toContain(EMAIL);
    expect(state.refreshes).toBe(0); expect(state.homes).not.toContain('/(member)');
    expect([...state.store.keys()].every((key) => key === KEY)).toBe(true);
    await press(view, /different.*account/i); expect(state.store.get(KEY)).toBe(TOKEN);
  });
  it.each(['staff', 'platform', 'impersonation'])('%s receives D1 and a switch without mutation', async (kind) => {
    state.identity = { ...state.identity, kind, role: 'gym_owner' };
    const view = await screen();
    expect(state.posts).toEqual([]); expect(text(view.tree)).toMatch(/already joined|already linked/i); expect(text(view.tree)).toContain(EMAIL);
    await press(view, /different.*account/i); expect(state.store.get(KEY)).toBe(TOKEN);
  });
  it.each(['landing', 'saved'] as const)('INV-030 %s account recovery saves then signs out and opens Google chooser in one press', async (kind) => {
    state.store.set(KEY, TOKEN); state.outcome = 'email_mismatch';
    if (kind === 'saved') state.identity = { kind: 'unlinked' };
    const view = await screen(kind);
    if (kind === 'saved') await press(view, /Link my membership/i);
    state.events = []; state.oauth = []; state.signOuts = 0;
    await press(view, /different.*account/i);
    expect(state.store.get(KEY)).toBe(TOKEN);
    expect(state.signOuts).toBe(1); expect(state.oauth).toHaveLength(1);
    expect(state.events.indexOf('save')).toBeGreaterThanOrEqual(0);
    expect(state.events.indexOf('save')).toBeLessThan(state.events.indexOf('signout'));
    expect(state.events.indexOf('signout')).toBeLessThan(state.events.indexOf('oauth'));
    expect(state.oauth[0]).toMatchObject({ provider: 'google', options: { queryParams: { prompt: 'select_account' } } });
    expect(state.homes).not.toContain('/sign-in');
  });
  it.each(['landing', 'saved'] as const)('INV-030 %s temporary error envelope shows retry, never an expired/replaced refusal or home', async (kind) => {
    state.apiError = 'invite_failed'; state.store.set(KEY, TOKEN);
    if (kind === 'saved') state.identity = { kind: 'unlinked' };
    const view = await screen(kind);
    if (kind === 'saved') await press(view, /Link my membership/i);
    expect(text(view.tree)).toMatch(/try again|retry|connection|could not|couldn.t/i);
    expect(text(view.tree)).not.toMatch(/expired|replaced/i);
    expect(state.homes).not.toContain('/(member)'); expect(state.refreshes).toBe(0);
  });
  it.each(Object.entries(REFUSALS))('INV-030 keeps the known %s refusal copy distinct from temporary failures', async (outcome, message) => {
    state.outcome = outcome;
    const view = await screen();
    expect(text(view.tree)).toContain(message); expect(state.refreshes).toBe(0); expect(state.homes).not.toContain('/(member)');
  });
});

describe('INV-029/INV-030 full native OAuth callback invite continuity', () => {
  beforeEach(() => { state.signedIn = true; state.routeParams = { code: 'native-callback-test-code' }; });
  it.each(['member', 'staff', 'platform'])('%s resumes the secure saved invite before ordinary role routing', async (kind) => {
    state.identity = { kind, userId: 'u1', tenantId: 't1', memberId: 'm1', staffId: 's1', role: kind === 'platform' ? 'super_admin' : 'front_desk' };
    state.store.set(KEY, TOKEN);
    await screen('callback');
    expect(state.homes.some((path) => typeof path === 'string' && path.includes('/invite/') && path.includes(TOKEN))).toBe(true);
    expect(state.homes.some((path) => path === '/(member)' || path === '/(desk)')).toBe(false);
    expect(state.posts).toEqual([]);
  });
  it.each(['member', 'staff', 'platform'])('%s without a saved invite retains ordinary routing', async (kind) => {
    state.identity = { kind, userId: 'u1', tenantId: 't1', memberId: 'm1', staffId: 's1', role: kind === 'platform' ? 'super_admin' : 'front_desk' };
    await screen('callback');
    expect(state.homes.length).toBeGreaterThan(0);
    expect(state.homes.every((path) => !String(path).includes('/invite/'))).toBe(true);
    expect(state.posts).toEqual([]);
  });
  it('malformed saved token is discarded safely without resuming an invite', async () => {
    state.identity = { kind: 'member', userId: 'u1', tenantId: 't1', memberId: 'm1' };
    state.store.set(KEY, '../bad-token?private=1');
    const view = await screen('callback');
    expect(state.homes.every((path) => !String(path).includes('bad-token') && !String(path).includes('/invite/'))).toBe(true);
    expect(text(view.tree)).not.toContain('private=1'); expect(state.posts).toEqual([]);
  });
  it('secure storage failure gives honest recovery without losing a possible invite to a false home', async () => {
    state.identity = { kind: 'member', userId: 'u1', tenantId: 't1', memberId: 'm1' }; state.storageFailure = true;
    const view = await screen('callback');
    expect(text(view.tree)).toMatch(/try again|retry|unable|could not|couldn.t/i);
    expect(state.homes).toEqual([]); expect(state.posts).toEqual([]);
  });
});
