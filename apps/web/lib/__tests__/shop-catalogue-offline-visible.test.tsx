import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, isValidElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

type Attributes = Record<string, unknown>;
const harness = vi.hoisted(() => ({ slots: [] as unknown[], cursor: 0, effects: [] as Array<() => unknown>, online: false, listeners: new Map<string, Set<() => void>>(), requests: [] as string[], audiences: [] as string[] }));
vi.mock('react', async original => { const actual = await original<typeof import('react')>(); return { ...actual,
  useState: <T,>(initial: T | (() => T)) => { const index = harness.cursor++; if (!(index in harness.slots)) harness.slots[index] = typeof initial === 'function' ? (initial as () => T)() : initial; return [harness.slots[index] as T, (next: T | ((previous: T) => T)) => { harness.slots[index] = typeof next === 'function' ? (next as (previous: T) => T)(harness.slots[index] as T) : next; }]; },
  useRef: <T,>(initial: T) => { const index = harness.cursor++; if (!(index in harness.slots)) harness.slots[index] = { current: initial }; return harness.slots[index]; },
  useEffect: (effect: () => unknown, dependencies?: unknown[]) => { const index = harness.cursor++; const previous = harness.slots[index] as unknown[] | undefined; if (!previous || !dependencies || dependencies.some((item, offset) => !Object.is(item, previous[offset]))) { harness.slots[index] = dependencies; harness.effects.push(effect); } },
  useMemo: <T,>(factory: () => T) => factory(), useCallback: <T,>(callback: T) => callback };
});
vi.mock('next/link', () => ({ default: (props: Attributes) => createElement('a', props) }));
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }), redirect: (path: string) => { throw new Error(`Unexpected redirect: ${path}`); }, usePathname: () => '/shop', useSearchParams: () => new URLSearchParams() }));
vi.mock('../../app/preview-context', () => ({ usePreviewReadOnly: () => false }));
vi.mock('../identity-session', () => ({ requireAudience: async (audience: string) => { harness.audiences.push(audience); return { identity: { kind: 'staff', userId: '72000000-0000-4000-8000-000000000081', tenantId: '72000000-0000-4000-8000-000000000082', staffId: '72000000-0000-4000-8000-000000000083', role: 'gym_owner' }, supabase: { from: () => { const query = { select: () => query, eq: () => query, single: async () => ({ data: { name: 'Empty visible gym', timezone: 'Asia/Kolkata', business_type: 'gym' }, error: null }), maybeSingle: async () => ({ data: { name: 'Empty visible gym', timezone: 'Asia/Kolkata', business_type: 'gym' }, error: null }) }; return query; } } }; } }));
vi.mock('../shop-console', () => ({ loadShopProducts: async () => ({ items: [], next: null }), loadShopCategories: async () => [] }));
function expand(node: ReactNode): ReactNode { if (Array.isArray(node)) return node.map(expand); if (!isValidElement<Attributes>(node)) return node; if (typeof node.type === 'function') return expand((node.type as (props: Attributes) => ReactNode)(node.props)); return createElement(node.type, { ...node.props, children: expand(node.props.children as ReactNode) }); }
async function markup(tree: ReactNode) { let resolved: ReactNode = tree; for (let pass = 0; pass < 3; pass++) { harness.cursor = 0; resolved = expand(tree); const effects = harness.effects.splice(0); for (const effect of effects) effect(); await Promise.resolve(); } return renderToStaticMarkup(resolved); }
beforeEach(() => { harness.slots = []; harness.cursor = 0; harness.effects = []; harness.online = false; harness.listeners.clear(); harness.requests = []; harness.audiences = []; vi.stubGlobal('navigator', { get onLine() { return harness.online; } }); vi.stubGlobal('window', { addEventListener: (name: string, listener: () => void) => { const group = harness.listeners.get(name) ?? new Set(); group.add(listener); harness.listeners.set(name, group); }, removeEventListener: (name: string, listener: () => void) => harness.listeners.get(name)?.delete(listener) }); vi.stubGlobal('fetch', (url: string) => { harness.requests.push(url); throw new Error('No empty-catalogue command is authorized'); }); });
afterEach(() => vi.unstubAllGlobals());
describe('SHP-017/Q10 successful empty console catalogue connection status', () => {
  it('keeps truthful connection notice even without a product panel and clears it without auto commands on reconnect', async () => {
    const { default: ShopPage } = await import('../../app/(console)/shop/page');
    const tree = await ShopPage(); const offline = await markup(tree);
    expect(harness.audiences).toEqual(['console']);
    expect(offline).toContain('No products or services yet.');
    expect(offline).not.toContain('Photo and category');
    expect(offline, 'Empty catalogue still exposes current browser connection state').toMatch(/offline/i);
    expect(harness.requests).toEqual([]);
    harness.online = true; for (const listener of harness.listeners.get('online') ?? []) listener();
    const reconnected = await markup(tree); expect(reconnected).toContain('No products or services yet.'); expect(reconnected).not.toMatch(/offline/i); expect(harness.requests).toEqual([]);
  });
});
