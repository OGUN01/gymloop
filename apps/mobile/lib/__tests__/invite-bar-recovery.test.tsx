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
} }));
const TOKEN = 'Q'.repeat(43);
// Independently computed SHA-256 of the fixed UTF-8 token, using .NET SHA256.
const TOKEN_HASH = '9cdc7469f022f9e7965d22eff1ab2c260adcd0c23b98d199c519762f3a0be959';
const KEY = 'gymloop.pending-invite';
const EMAIL = 'viewer.google@example.com';
const GYM = 'Iron Box Fitness';
const NOTICE = `By linking, you let ${GYM} connect this Google account (your name and email) to your membership record. FitCruxx processes it on ${GYM}'s behalf to show you your visits, payments and messages. Ask ${GYM} to unlink it at any time.`;
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
  View: host('view'), Text: host('text'), Pressable: host('button'), TextInput: host('input'), ScrollView: host('scroll'),
  StyleSheet: { create: (value: unknown) => value }, Platform: { OS: 'android', select: (value: Record<string, unknown>) => value.android },
  Linking: { openURL: async (url: string) => { state.urls.push(url); } },
}));
vi.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ token: TOKEN }), useGlobalSearchParams: () => ({ token: TOKEN }),
  router: { replace: (path: string) => state.homes.push(path), push: (path: string) => state.homes.push(path) },
  useRouter: () => ({ replace: (path: string) => state.homes.push(path), push: (path: string) => state.homes.push(path) }),
  Link: host('link'), Redirect: (props: { href: string }) => { state.homes.push(props.href); return null; },
}));
vi.mock('expo-secure-store', () => ({
  getItemAsync: async (key: string) => state.store.get(key) ?? null,
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
vi.mock('../../components/ui', () => ({ FONT: new Proxy({}, { get: () => 'test-font' }), ...Object.fromEntries([
  'Screen', 'Eyebrow', 'Title', 'Body', 'Surface', 'Field', 'LoadingState', 'StateMessage', 'ActionButton',
].map((name) => [name, (props: Record<string, unknown>) => createElement(name === 'ActionButton' ? 'button' : name === 'Field' ? 'input' : 'view', props,
  [props.title, props.message, props.label, props.children].filter((value) => value !== undefined) as ReactNode)])) }));
const supabase = {
  rpc: async (name: string, args: unknown) => { state.rpc.push({ name, args }); if (state.peekFailure) throw new Error('connection unavailable'); return { data: state.peek, error: null }; },
  from: () => { throw new Error('native invite must never read person records'); },
  auth: {
    getUser: async () => ({ data: { user: state.signedIn ? { id: 'u1', email: EMAIL } : null }, error: null }),
    refreshSession: async () => { state.refreshes += 1; state.events.push('refresh'); return { data: { session: {} }, error: null }; },
    signOut: async () => { state.signOuts += 1; return { error: null }; },
    signInWithOAuth: async (options: unknown) => { state.events.push('oauth'); state.oauth.push(options); return { data: { url: 'https://google.example/chooser' }, error: null }; },
  },
};
const api = { post: async (path: string, body: unknown) => {
  state.posts.push({ path, body }); state.events.push('post'); if (state.network) throw new Error('offline');
  return { ok: true, data: { outcome: state.outcome, gymName: 'Forbidden other gym' } };
} };
vi.mock('../mobile-context', () => ({ useMobile: () => ({
  identity: state.identity, session: state.signedIn ? { user: { id: 'u1', email: EMAIL } } : null,
  loading: false, ready: true, supabase, api, webOrigin: 'https://app.example', palette: UI_TOKENS.colors.dark,
  signOut: async () => { state.signOuts += 1; },
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
async function screen(kind: 'landing' | 'saved' = 'landing') {
  const Screen = kind === 'landing' ? (await import('../../app/invite/[token]')).default : (await import('../../app/not-linked')).default;
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
});
describe('INV-029 native landing consent and direct Google', () => {
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
});
