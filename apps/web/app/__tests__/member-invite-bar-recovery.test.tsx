import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { cloneElement, createElement, isValidElement, type ReactElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

/** INV-030, owner-frozen v1.4: execute the real landing and its client effects.
 * Only session, browser and HTTP I/O are replaced. No implementation/holdout read.
 */
const { state } = vi.hoisted(() => ({ state: {
  identity: {} as Record<string, unknown>, slots: [] as unknown[], cursor: 0,
  effects: [] as Array<() => unknown>, requests: [] as Array<{ url: string; init: RequestInit }>,
  outcome: 'already_linked_here', network: false, homes: [] as string[],
  cookie: '', signOuts: 0, oauth: [] as unknown[],
} }));
const TOKEN = 'Q'.repeat(43);
const EMAIL = 'viewer.google@example.com';
const MEMBER = { kind: 'member', userId: 'u1', tenantId: 't1', memberId: 'm1' };
vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  const slot = (initial: unknown) => { const key = state.cursor++; if (!(key in state.slots)) state.slots[key] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return key; };
  return { ...actual,
    useState: (initial: unknown) => { const key = slot(initial); return [state.slots[key], (next: unknown) => { state.slots[key] = typeof next === 'function' ? (next as (old: unknown) => unknown)(state.slots[key]) : next; }]; },
    useRef: (initial: unknown) => state.slots[slot({ current: initial })],
    useEffect: (effect: () => unknown, deps?: unknown[]) => { const key = state.cursor++; const old = state.slots[key] as unknown[] | undefined; if (!old || !deps || deps.some((value, index) => !Object.is(value, old[index]))) { state.slots[key] = deps; state.effects.push(effect); } },
    useMemo: (make: () => unknown) => make(), useCallback: (callback: unknown) => callback,
    useTransition: () => [false, (run: () => unknown) => run()], useId: () => 'invite-recovery',
  };
});
vi.mock('next/navigation', () => ({
  redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); },
  useRouter: () => ({ replace: (path: string) => state.homes.push(path), push: (path: string) => state.homes.push(path), refresh: () => undefined }),
}));
vi.mock('next/link', () => ({ default: (props: Record<string, unknown>) => createElement('a', props) }));
vi.mock('next/image', () => ({ default: (props: Record<string, unknown>) => createElement('img', props) }));
vi.mock('next/headers', () => ({ cookies: async () => ({
  get: (name: string) => name === 'fitcruxx_invite' && state.cookie ? { value: state.cookie } : undefined,
  getAll: () => [], set: (...args: unknown[]) => { const entry = args[0]; state.cookie = typeof entry === 'object' && entry ? String((entry as { value: string }).value) : String(args[1]); },
}) }));
vi.mock('next/cache', () => ({ revalidatePath: () => undefined }));
vi.mock('@gymloop/shared', async (original) => ({ ...(await original<typeof import('@gymloop/shared')>()), webAppEnv: () => ({ WEB_APP_URL: 'https://app.example' }), serverEnv: () => ({ WEB_APP_URL: 'https://app.example' }) }));
const client = () => ({
  auth: {
    getUser: async () => ({ data: { user: { id: 'u1', email: EMAIL } }, error: null }),
    signOut: async () => { state.signOuts += 1; return { error: null }; },
    signInWithOAuth: async (options: unknown) => { state.oauth.push(options); return { data: { url: 'https://google.example/chooser' }, error: null }; },
  },
  rpc: () => { throw new Error('INV-030 forbids redemption during GET/render'); },
  from: () => { throw new Error('The invite landing never reads member records'); },
});
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../lib/identity-session', () => ({ readIdentity: async () => ({ signedIn: true, identity: state.identity, supabase: client() }) }));
vi.mock('../../lib/member-invites', () => ({ peekInvite: async () => null, loadMemberAppAccess: async () => null }));
type Element = ReactElement<Record<string, unknown>>;
function expand(node: ReactNode): ReactNode {
  if (Array.isArray(node)) return node.map(expand);
  if (!isValidElement<Record<string, unknown>>(node)) return node;
  if (typeof node.type === 'function') return expand((node.type as (props: unknown) => ReactNode)(node.props));
  return cloneElement(node, {}, expand(node.props.children as ReactNode));
}
function nodes(node: ReactNode): Element[] {
  if (Array.isArray(node)) return node.flatMap(nodes);
  if (!isValidElement<Record<string, unknown>>(node)) return [];
  return [node, ...nodes(node.props.children as ReactNode)];
}
const text = (html: string) => html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');
async function open() {
  const Page = (await import('../invite/[token]/page')).default;
  const root = await Page({ params: Promise.resolve({ token: TOKEN }) });
  expect(state.requests, 'a server render cannot perform the mutating POST').toEqual([]);
  const draw = () => { state.cursor = 0; return expand(root); };
  let tree = draw();
  for (let pass = 0; pass < 5; pass += 1) { for (const effect of state.effects.splice(0)) await effect(); await new Promise((resolve) => setTimeout(resolve, 0)); tree = draw(); }
  return { tree, html: renderToStaticMarkup(tree), draw };
}
async function switchAccount(tree: ReactNode) {
  const form = nodes(tree).find((node) => node.type === 'form' && typeof node.props.action === 'function'
    && text(renderToStaticMarkup(node)).match(/different.*account/i));
  const button = nodes(tree).find((node) => node.type === 'button' && text(renderToStaticMarkup(node)).match(/different.*account/i));
  expect(form || button, 'one-tap account switch').toBeDefined();
  if (form) await (form.props.action as (data: FormData) => Promise<unknown>)(new FormData()).catch(() => undefined);
  else await (button?.props.onClick as () => unknown)();
}
beforeEach(() => {
  state.identity = MEMBER; state.slots = []; state.cursor = 0; state.effects = []; state.requests = []; state.homes = [];
  state.outcome = 'already_linked_here'; state.network = false; state.cookie = TOKEN; state.signOuts = 0; state.oauth = [];
  vi.stubGlobal('window', { location: { assign: (path: string) => state.homes.push(path), replace: (path: string) => state.homes.push(path), href: '' } });
  vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
    state.requests.push({ url: String(url), init });
    if (state.network) throw new TypeError('offline');
    return new Response(JSON.stringify({ ok: true, data: { outcome: state.outcome, gymName: 'Do not expose another gym' } }), { status: 200, headers: { 'content-type': 'application/json' } });
  });
});
afterEach(() => vi.unstubAllGlobals());
describe('INV-030 web landing replay and recovery', () => {
  it('checks a signed-in member using one client POST and opens home only for already_linked_here', async () => {
    await open();
    expect(state.requests).toHaveLength(1);
    const request = state.requests[0];
    expect(request?.url).toBe('/api/member-invites/redeem'); expect(request?.init.method).toBe('POST');
    expect(JSON.parse(String(request?.init.body))).toEqual({ token: TOKEN });
    expect(state.homes).toContain('/member');
  });
  it.each(['linked', 'invite_unavailable', 'account_already_linked', 'unknown_outcome'])('does not claim successful replay for %s and preserves account-switch recovery', async (outcome) => {
    state.outcome = outcome;
    const view = await open();
    expect(state.homes).toEqual([]); expect(text(view.html)).toContain(EMAIL);
    expect(view.html).not.toContain('Do not expose another gym');
    await switchAccount(view.tree);
    expect(state.cookie).toBe(TOKEN); expect(state.signOuts).toBeGreaterThan(0);
  });
  it('network failure is recoverable and keeps the invite', async () => {
    state.network = true;
    const view = await open();
    expect(text(view.html)).toContain(EMAIL); expect(text(view.html)).toMatch(/try again|connection|offline|unable/i);
    expect(state.homes).toEqual([]); await switchAccount(view.tree); expect(state.cookie).toBe(TOKEN);
  });
  it.each(['staff', 'platform', 'impersonation'])('%s gets D1 and account switching without a redemption POST', async (kind) => {
    state.identity = { ...MEMBER, kind, role: 'gym_owner' };
    const view = await open();
    expect(state.requests).toEqual([]); expect(text(view.html)).toContain(EMAIL);
    expect(text(view.html)).toMatch(/already joined|already linked/i);
    await switchAccount(view.tree); expect(state.cookie).toBe(TOKEN);
  });
});
