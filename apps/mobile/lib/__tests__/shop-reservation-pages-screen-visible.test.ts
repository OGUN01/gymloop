import { beforeEach, describe, expect, it, vi } from 'vitest';

// SHP-PAGE-006, SHP-PAGE-007, SHP-PAGE-008: frozen hook state at the rendered screen.
type Node = { type: unknown; props: Record<string, unknown> };
const h = vi.hoisted(() => ({ cursor: 0, slots: [] as unknown[], effects: [] as Array<() => unknown>, changed: false, online: true, pages: null as unknown, api: null as unknown, post: vi.fn(), loadMore: vi.fn(), reload: vi.fn(), scroll: vi.fn() }));
vi.mock('react', async original => {
  const actual = await original<Record<string, unknown>>();
  const memo = (factory: () => unknown, deps?: unknown[]) => { const index = h.cursor++; const old = h.slots[index] as { deps?: unknown[]; value: unknown } | undefined; if (!old || !deps || deps.some((value, offset) => !Object.is(value, old.deps?.[offset]))) h.slots[index] = { deps, value: factory() }; return (h.slots[index] as { value: unknown }).value; };
  const hooks = {
    useState: (initial: unknown) => { const index = h.cursor++; if (!(index in h.slots)) h.slots[index] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return [h.slots[index], (next: unknown) => { const value = typeof next === 'function' ? (next as (value: unknown) => unknown)(h.slots[index]) : next; if (!Object.is(value, h.slots[index])) { h.slots[index] = value; h.changed = true; } }]; },
    useRef: (initial: unknown) => memo(() => ({ current: initial }), []), useMemo: memo, useCallback: (callback: unknown, deps?: unknown[]) => memo(() => callback, deps), useEffect: (effect: () => unknown, deps?: unknown[]) => memo(() => { h.effects.push(effect); return undefined; }, deps),
  };
  return { ...actual, ...hooks, default: { ...(actual.default as Record<string, unknown> | undefined), ...hooks } };
});
const identity = { kind: 'member', userId: 'page-screen-user', tenantId: 'page-screen-tenant', memberId: 'page-screen-member', role: 'member' };
const api = { post: h.post };
vi.mock('../mobile-context', () => ({ useMobile: () => ({ identity, api: h.api, ready: true, session: {}, palette: {}, businessType: 'gym', appearance: 'light', nouns: { place: 'gym', plural: 'gyms', member: 'member', members: 'members', trainer: 'trainer', class: 'class', classes: 'classes' }, supabase: {}, signOut: vi.fn() }) }));
vi.mock('../use-member-shop-pages', () => ({ useMemberShopPages: () => h.pages }));
vi.mock('../use-member-snapshot', () => ({ useMemberSnapshot: () => ({ data: { gym: { name: 'Page Gym', displayName: 'Page Gym', timezone: 'Asia/Kolkata' } }, error: null, loading: false, reload: vi.fn() }) }));
vi.mock('../use-member-plans', () => ({ useMemberPlans: () => ({ state: { phase: 'ready', view: { plans: [], truncated: false, heldUnavailable: false, held: null }, loadedAt: null, staleReason: null, offline: false }, reload: vi.fn(async () => undefined) }) }));
vi.mock('expo-network', () => ({ useNetworkState: () => ({ isConnected: h.online, isInternetReachable: h.online }), getNetworkStateAsync: async () => ({ isConnected: h.online, isInternetReachable: h.online }), addNetworkStateListener: () => ({ remove: vi.fn() }) }));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: vi.fn(), replace: vi.fn() }), useLocalSearchParams: () => ({}), Link: 'Link', Redirect: 'Redirect' }));
vi.mock('expo-secure-store', () => ({ setItemAsync: vi.fn(), getItemAsync: async () => null, deleteItemAsync: vi.fn() }));
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', Image: 'Image', ScrollView: (props: Record<string, unknown>) => { const ref = props.ref as { current: unknown } | undefined; if (ref) ref.current = { scrollTo: h.scroll }; return { type: 'ScrollView', props }; }, Modal: 'Modal', ActivityIndicator: 'ActivityIndicator', TextInput: 'TextInput', StyleSheet: { create: (styles: unknown) => styles }, AppState: { addEventListener: () => ({ remove: vi.fn() }) }, useColorScheme: () => 'light' }));
vi.mock('lucide-react-native', () => Object.fromEntries(['ShoppingBag', 'Package', 'Image', 'ImageOff', 'Plus', 'Minus', 'RefreshCw', 'X', 'ChevronRight', 'Check', 'Clock'].map(name => [name, name])));
vi.mock('../../components/ui', () => ({ ...Object.fromEntries(['Screen', 'Eyebrow', 'Title', 'Display', 'Body', 'Rule', 'Status', 'Row', 'LedgerSection', 'SheetHeader', 'ActionButton', 'RowAction', 'StateMessage', 'EmptyState', 'LoadingState', 'Field', 'ChoiceList'].map(type => [type, (props: Record<string, unknown>) => ({ type, props })])), Sheet: (props: Record<string, unknown>) => props.visible ? { type: 'Sheet', props } : null }));
const id = (n: number) => `85000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const reservations = Array.from({ length: 8 }, (_, index) => ({ reservationId: id(index + 100), itemId: id(index + 10), itemName: `Reservation sentinel ${index + 1}`, section: 'products', quantity: 1, unitPricePaise: '100', totalPaise: '100', currency: 'INR', state: index < 5 ? 'reserved' : 'expired', createdAt: '2026-10-06T00:00:00Z', expiresAt: index < 5 ? '2099-10-07T00:00:00Z' : '2026-10-07T00:00:00Z', cancelReason: null, termsChanged: false, orderId: null, imageUrl: null }));
const product = { itemId: id(999), section: 'products', name: 'Private selected product sentinel', description: 'Private product detail sentinel', pricePaise: '9007199254740993', currency: 'INR', gstRateBp: 0, validityDays: 7, cancellationTerms: 'Ask the desk', quoteVersion: id(998), categoryId: null, categoryName: null, imageUrl: null, availability: 'available', availableQuantity: 1 };
const response = { items: [product], reservations, truncated: false, serverTime: '2026-10-07T00:00:00Z' };
let pages: { view: { scope: string; response: typeof response; savedAt: string; stale: boolean } | null; loading: boolean; loadingMore: boolean; error: string | null; visibleCount: number; hasMore: boolean; reload: typeof h.reload; loadMore: typeof h.loadMore };
let screen: () => unknown;
let nodes: Node[];
function flatten(value: unknown) { if (Array.isArray(value)) { value.forEach(flatten); return; } if (!value || typeof value !== 'object' || !('props' in value)) return; const node = value as Node; if (typeof node.type === 'function') { flatten(node.type(node.props)); return; } nodes.push(node); flatten(node.props.children); flatten(node.props.footer); flatten(node.props.trailing); }
function words(value: unknown): string { if (Array.isArray(value)) return value.map(words).join(' '); return typeof value === 'string' || typeof value === 'number' ? String(value) : ''; }
function text() { return nodes.map(node => ['children', 'title', 'meta', 'detail', 'message', 'label', 'accessibilityLabel'].map(key => words(node.props[key])).join(' ')).join(' ').replace(/\s+/g, ' '); }
function action(label: RegExp) { const node = nodes.find(node => typeof node.props.onPress === 'function' && ['children', 'title', 'label', 'accessibilityLabel'].some(key => label.test(words(node.props[key]).trim()))); expect(node, `Missing public screen action ${label}`).toBeDefined(); return node!; }
function draw() { h.cursor = 0; h.changed = false; nodes = []; flatten(screen()); }
async function render() { for (let pass = 0; pass < 30; pass++) { h.cursor = 0; h.changed = false; nodes = []; flatten(screen()); h.effects.splice(0).forEach(effect => effect()); await new Promise(resolve => setTimeout(resolve, 0)); if (!h.changed && h.effects.length === 0) return; } throw new Error('Shop render did not settle'); }
async function press(label: RegExp) { await (action(label).props.onPress as () => unknown)(); await render(); }
function sheetText() { const all = nodes; nodes = []; all.filter(node => node.type === 'Sheet').forEach(flatten); const result = text(); nodes = all; return result; }
function sheetCommand(kind: 'reserve' | 'cancel') { const label = kind === 'reserve' ? /Confirm reservation|Reserve/i : /Cancel/i; return [...nodes].reverse().find(node => typeof node.props.onPress === 'function' && ['children', 'title', 'label', 'accessibilityLabel'].some(key => label.test(words(node.props[key]).trim()))); }
async function openSheet(kind: 'reserve' | 'cancel') {
  await render();
  if (kind === 'reserve') { await press(new RegExp(product.name)); const next = sheetCommand(kind); expect(next).toBeDefined(); await (next!.props.onPress as () => unknown)(); await render(); }
  else await press(/Cancel/i);
  const name = kind === 'reserve' ? product.name : reservations[0]!.itemName;
  expect(sheetText(), 'Actual confirmation contains the selected private facts').toContain(name);
  const control = sheetCommand(kind); expect(control, 'Existing confirmation command is reachable').toBeDefined();
  expect(control!.props.disabled ?? (control!.props.accessibilityState as { disabled?: boolean })?.disabled).not.toBe(true);
  return { control: control!, name };
}
beforeEach(async () => {
  vi.resetModules(); h.cursor = 0; h.slots = []; h.effects = []; h.changed = false; h.online = true; h.api = api; h.scroll.mockReset(); h.reload.mockReset().mockResolvedValue(undefined);
  h.loadMore.mockReset().mockImplementation(async () => { pages.visibleCount = 8; pages.hasMore = false; });
  pages = { view: { scope: 'page-screen-user:page-screen-tenant:page-screen-member', response, savedAt: '2026-10-07T00:00:00Z', stale: false }, loading: false, loadingMore: false, error: null, visibleCount: 3, hasMore: true, reload: h.reload, loadMore: h.loadMore }; h.pages = pages;
  h.post.mockReset().mockImplementation(async (path: string) => path === '/api/shop/catalogue' ? { ok: true, data: response } : { ok: false, status: 409, error: { code: 'reservation_expired', message: 'Expired' } });
  const cache = await import('../shop-cache'); await cache.clearShopCache(cache.nativeShopCache);
  screen = (await import('../../app/(member)/shop')).default;
});

describe('SHP-PAGE paged native Shop screen integration', () => {
  it('shows three total rows and exactly two hidden active holds with cancellation accessible', async () => {
    await render(); expect(reservations.filter(row => text().includes(row.itemName))).toHaveLength(3);
    expect(text()).toMatch(/2\s+(?:more\s+|additional\s+)?active\s+(?:holds|reservations)|(?:more|additional|hidden)\s+active\s+(?:holds|reservations)[^0-9]*2/i);
    expect(action(/Cancel/i)).toBeDefined();
  });
  it('Load more delegates the bounded action, reveals five and preserves scrolling', async () => {
    await render(); h.scroll.mockClear(); await press(/^Load more$/i);
    expect(h.loadMore).toHaveBeenCalledTimes(1); expect(reservations.filter(row => text().includes(row.itemName))).toHaveLength(8); expect(h.scroll).not.toHaveBeenCalled();
    expect(nodes.some(node => typeof node.props.onPress === 'function' && /^Load more$/i.test(words(node.props.children ?? node.props.title ?? node.props.label)))).toBe(false);
  });
  it('pending continuation keeps current rows and disables its control', async () => {
    pages.loadingMore = true; await render(); const control = action(/Load more|Loading/i);
    expect(control.props.disabled ?? (control.props.accessibilityState as { disabled?: boolean })?.disabled).toBe(true);
    expect(reservations.filter(row => text().includes(row.itemName))).toHaveLength(3);
  });
  it.each([true, false])('cancel outcome accepted=%s refreshes through the page hook', async accepted => {
    await render(); h.post.mockImplementation(async (path: string) => path === '/api/shop/catalogue' ? { ok: true, data: response } : accepted ? { ok: true, data: {} } : { ok: false, status: 409, error: { code: 'reservation_expired', message: 'Expired' } });
    await press(/Cancel/i);
    if (!h.post.mock.calls.some(([path]) => String(path).includes('/cancel'))) {
      const confirm = [...nodes].reverse().find(node => typeof node.props.onPress === 'function' && ['children', 'title', 'label', 'accessibilityLabel'].some(key => /Cancel/i.test(words(node.props[key]).trim())));
      expect(confirm, 'Existing cancellation confirmation is reachable').toBeDefined(); await (confirm!.props.onPress as () => unknown)(); await render();
    }
    expect(h.post.mock.calls.some(([path]) => String(path).includes('/cancel'))).toBe(true); expect(h.reload).toHaveBeenCalledTimes(1);
  });
});

describe('SHP-PAGE-008 open sheets follow current page authorization', () => {
  it.each(['reserve', 'cancel'] as const)('%s sheet immediately redacts private facts when the current hook view disappears', async kind => {
    const opened = await openSheet(kind); const calls = h.post.mock.calls.length;
    pages.view = null; pages.loading = true; draw();
    expect(sheetText()).not.toContain(opened.name); expect(text()).not.toContain(opened.name);
    await (opened.control.props.onPress as () => unknown)(); await render();
    expect(h.post).toHaveBeenCalledTimes(calls); expect(sheetText()).not.toContain(opened.name);
  });
  it.each(['reserve', 'cancel'] as const)('%s sheet immediately redacts and revokes retained handlers after same-caller refusal', async kind => {
    const opened = await openSheet(kind); const calls = h.post.mock.calls.length;
    pages.view = null; pages.error = 'Your access was refused. Sign in again.'; draw();
    expect(sheetText()).not.toContain(opened.name); expect(text()).not.toContain(opened.name);
    await (opened.control.props.onPress as () => unknown)(); await render();
    expect(h.post).toHaveBeenCalledTimes(calls); expect(sheetText()).not.toContain(opened.name);
  });
  it.each(['reserve', 'cancel'] as const)('%s selection belongs to the API capability that opened it', async kind => {
    const opened = await openSheet(kind); const calls = h.post.mock.calls.length; const replacement = vi.fn();
    h.api = { post: replacement }; draw();
    expect(sheetText()).not.toContain(opened.name);
    await (opened.control.props.onPress as () => unknown)(); await render();
    expect(h.post).toHaveBeenCalledTimes(calls); expect(replacement).not.toHaveBeenCalled(); expect(sheetText()).not.toContain(opened.name);
  });
  it.each(['reserve', 'cancel'] as const)('%s mutation requires a current fresh view even from a retained enabled handler', async kind => {
    const opened = await openSheet(kind); const calls = h.post.mock.calls.length;
    pages.view = { ...pages.view!, stale: true }; pages.error = 'Refresh the shop before trying again.'; draw();
    const current = sheetCommand(kind);
    if (nodes.some(node => node.type === 'Sheet') && current) expect(current.props.disabled ?? (current.props.accessibilityState as { disabled?: boolean })?.disabled).toBe(true);
    await (opened.control.props.onPress as () => unknown)(); await render();
    expect(h.post).toHaveBeenCalledTimes(calls);
  });
  it.each(['reserve', 'cancel'] as const)('late %s completion cannot restore a refused caller\'s sheet or cache', async kind => {
    const opened = await openSheet(kind); let resolve!: (value: unknown) => void;
    h.post.mockImplementation(() => new Promise(done => { resolve = done; }));
    const command = (opened.control.props.onPress as () => Promise<void>)(); await render();
    expect(h.post).toHaveBeenCalledTimes(1);
    pages.view = null; pages.error = 'Your access was refused. Sign in again.';
    const cache = await import('../shop-cache'); await cache.clearShopCache(cache.nativeShopCache); draw();
    resolve({ ok: true, data: kind === 'reserve' ? { reservationId: id(997), expiresAt: '2099-10-07T00:00:00Z' } : {} });
    await command; await render();
    expect(sheetText()).not.toContain(opened.name); expect(text()).not.toContain(opened.name);
    expect(await cache.readShopCache(cache.nativeShopCache, 'page-screen-user:page-screen-tenant:page-screen-member')).toBeNull();
    h.online = false; await render(); expect(text()).not.toContain(opened.name);
  });
});
