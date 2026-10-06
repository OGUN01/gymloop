import { beforeEach, describe, expect, it, vi } from 'vitest';

// Test-only React/native boundary. This renders the actual screen and runs its
// hooks; all catalogue, cache and command decisions remain in the real modules.
type Node = { type: unknown; props: Record<string, unknown> };
const h = vi.hoisted(() => ({ cursor: 0, slots: [] as unknown[], effects: [] as Array<() => unknown>, changed: false, online: true, identity: { kind: 'member', userId: 'user-a', tenantId: 'tenant-a', memberId: 'member-a', role: 'member' } as Record<string, string>, post: vi.fn(), push: vi.fn(), queue: vi.fn(), persist: vi.fn() }));
function mockReactHooks(actual: Record<string, unknown>) {
  const memo = (factory: () => unknown, deps?: unknown[]) => {
    const index = h.cursor++; const previous = h.slots[index] as { deps?: unknown[]; value: unknown } | undefined;
    if (!previous || !deps || deps.some((value, offset) => !Object.is(value, previous.deps?.[offset]))) h.slots[index] = { deps, value: factory() };
    return (h.slots[index] as { value: unknown }).value;
  };
  const hooks = {
    useState: (initial: unknown) => {
      const index = h.cursor++;
      if (!(index in h.slots)) h.slots[index] = typeof initial === 'function' ? initial() : initial;
      return [h.slots[index], (next: unknown) => { const value = typeof next === 'function' ? next(h.slots[index]) : next; if (!Object.is(value, h.slots[index])) { h.slots[index] = value; h.changed = true; } }];
    },
    useRef: (initial: unknown) => memo(() => ({ current: initial }), []),
    useMemo: memo,
    useCallback: (callback: unknown, deps?: unknown[]) => memo(() => callback, deps),
    useEffect: (effect: () => unknown, deps?: unknown[]) => memo(() => { h.effects.push(effect); return undefined; }, deps),
  };
  return { ...actual, ...hooks, default: { ...(actual.default as Record<string, unknown>), ...hooks } };
}
vi.mock('react', async original => mockReactHooks(await original<Record<string, unknown>>()));
// Package-local React imports share the renderer mock, including default hooks.
const api = { post: h.post };
vi.mock('../mobile-context', () => ({ useMobile: () => ({ identity: h.identity, api, ready: true, nouns: { place: 'gym', plural: 'gyms', member: 'member', members: 'members', trainer: 'trainer', class: 'class', classes: 'classes' }, palette: {}, businessType: 'gym', appearance: 'light', supabase: {}, session: h.identity.kind === 'member' ? {} : null, signOut: vi.fn() }) }));
vi.mock('../use-member-snapshot', () => ({ useMemberSnapshot: () => ({ data: { gym: { name: 'Fixture Gym', displayName: 'Fixture Gym', timezone: 'Asia/Kolkata' } }, error: null, loading: false, reload: vi.fn() }) }));
vi.mock('expo-network', () => ({ useNetworkState: () => ({ isConnected: h.online, isInternetReachable: h.online }), getNetworkStateAsync: async () => ({ isConnected: h.online, isInternetReachable: h.online }), addNetworkStateListener: () => ({ remove: vi.fn() }) }));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: h.push, replace: vi.fn() }), useLocalSearchParams: () => ({}), Link: 'Link', Redirect: 'Redirect' }));
vi.mock('expo-secure-store', () => ({ setItemAsync: h.persist, getItemAsync: async () => null, deleteItemAsync: vi.fn() }));
vi.mock('../offline-check-in', () => ({ saveOfflineCheckIn: h.queue, loadOfflineCheckIns: async () => [], clearOfflineCheckIns: vi.fn(), shouldReplayOnSignal: () => false, createReplayCoordinator: () => ({ requestReplay: vi.fn() }) }));
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', Image: 'Image', ScrollView: 'ScrollView', Modal: 'Modal', ActivityIndicator: 'ActivityIndicator', TextInput: 'TextInput', StyleSheet: { create: (styles: unknown) => styles }, AppState: { addEventListener: () => ({ remove: vi.fn() }) }, useColorScheme: () => 'light' }));
vi.mock('lucide-react-native', () => ({ ShoppingBag: 'ShoppingBag', Package: 'Package', Image: 'ImageIcon', ImageOff: 'ImageOff', Plus: 'Plus', Minus: 'Minus', RefreshCw: 'RefreshCw', X: 'X', ChevronRight: 'ChevronRight', Check: 'Check', Clock: 'Clock' }));
vi.mock('../../components/ui', () => {
  const widgets = ['Screen', 'Eyebrow', 'Title', 'Display', 'Body', 'Rule', 'Status', 'Row', 'LedgerSection', 'SheetHeader', 'ActionButton', 'RowAction', 'StateMessage', 'EmptyState', 'LoadingState', 'Field', 'ChoiceList'];
  return { ...Object.fromEntries(widgets.map(type => [type, (props: Record<string, unknown>) => ({ type, props })])), Sheet: (props: Record<string, unknown>) => props.visible ? { type: 'Sheet', props } : null };
});
vi.mock('../use-member-plans', () => ({ useMemberPlans: () => ({ state: { phase: 'ready', view: { plans: [], truncated: false, heldUnavailable: false, held: null }, loadedAt: null, staleReason: null, offline: false }, reload: vi.fn(async () => undefined) }) }));
const item = { itemId: '72000000-0000-4000-8000-000000000701', section: 'products', name: 'Uncategorised product with a very long truthful catalogue name', description: 'A real uncategorised item', pricePaise: '199900', currency: 'INR', gstRateBp: 0, validityDays: 30, cancellationTerms: 'Ask desk', quoteVersion: '72000000-0000-4000-8000-000000000799', categoryId: null, categoryName: null, imageUrl: null, availability: 'available', availableQuantity: 2 };
const products = [
  { ...item, itemId: '72000000-0000-4000-8000-000000000702', name: 'Saved recovery category product', categoryId: '72000000-0000-4000-8000-000000000711', categoryName: 'Recovery essentials' },
  item,
  { ...item, itemId: '72000000-0000-4000-8000-000000000703', name: 'Saved hydration category product', categoryId: '72000000-0000-4000-8000-000000000712', categoryName: 'Hydration' },
  { ...item, itemId: '72000000-0000-4000-8000-000000000704', section: 'services', name: 'Actual assessment service' },
];
const reservations = Array.from({ length: 11 }, (_, index) => ({
  reservationId: `72000000-0000-4000-8000-${String(index + 800).padStart(12, '0')}`, itemId: item.itemId, itemName: `History reservation ${index + 1} sentinel`, section: 'products',
  quantity: 1, unitPricePaise: '199900', totalPaise: '199900', currency: 'INR', state: index < 5 ? 'reserved' : 'expired',
  createdAt: `2026-10-05T04:30:00.000${String(999 - index).padStart(3, '0')}Z`, expiresAt: index < 5 ? '2099-10-07T04:30:00Z' : '2026-10-06T03:30:00Z', cancelReason: null, termsChanged: false, orderId: null, imageUrl: null,
}));
let catalogue = { items: products, reservations, truncated: false, serverTime: '2026-10-06T04:30:00Z' };
function pageFixture(body: { mode: string; after?: { id: string } }) {
  const rows = catalogue.reservations;
  const start = body.mode === 'initial' ? 0 : rows.findIndex(row => row.reservationId === body.after?.id) + 1;
  const page = rows.slice(start, start + (body.mode === 'initial' ? 8 : 5));
  const last = page.at(-1);
  const nextAfter = start + page.length < rows.length && last ? { createdAt: last.createdAt, id: last.reservationId } : null;
  return body.mode === 'initial' ? { ...catalogue, mode: 'initial', reservations: page, nextAfter } : { mode: 'more', reservations: page, nextAfter, serverTime: catalogue.serverTime };
}
let screen: () => unknown;
let nodes: Node[] = [];
function flatten(value: unknown): void {
  if (Array.isArray(value)) { value.forEach(flatten); return; }
  if (!value || typeof value !== 'object' || !('props' in value)) return;
  const node = value as Node;
  if (typeof node.type === 'function') { flatten(node.type(node.props)); return; }
  nodes.push(node); flatten(node.props.children); flatten(node.props.footer); flatten(node.props.trailing);
}
async function render() {
  for (let pass = 0; pass < 30; pass++) {
    h.cursor = 0; h.changed = false; nodes = []; flatten(screen()); h.effects.splice(0).forEach(effect => effect());
    await new Promise(resolve => setTimeout(resolve, 0)); if (!h.changed && h.effects.length === 0) return;
  }
  throw new Error('Shop did not settle');
}
function words(value: unknown): string {
  if (typeof value === 'string' || typeof value === 'number') return String(value);
  if (Array.isArray(value)) return value.map(words).join(' ');
  return '';
}
function text() { return nodes.map(node => ['children', 'title', 'meta', 'detail', 'message', 'label', 'accessibilityLabel'].map(key => words(node.props[key])).join(' ')).join(' ').replace(/\s+/g, ' '); }
function action(label: RegExp) {
  const node = nodes.find(node => typeof node.props.onPress === 'function' && ['children', 'title', 'label', 'accessibilityLabel'].some(key => label.test(words(node.props[key]).trim())));
  expect(node, `Shop control ${label}`).toBeDefined(); return node!;
}
async function press(label: RegExp) { await (action(label).props.onPress as () => unknown)(); await render(); }
function shownReservations() { return reservations.filter(reservation => text().includes(reservation.itemName)); }
beforeEach(async () => {
  vi.resetModules(); h.cursor = 0; h.slots = []; h.effects = []; h.changed = false; h.online = true; h.identity = { kind: 'member', userId: 'user-a', tenantId: 'tenant-a', memberId: 'member-a', role: 'member' };
  h.push.mockReset(); h.persist.mockReset(); h.queue.mockReset(); catalogue = { items: products, reservations, truncated: false, serverTime: '2026-10-06T04:30:00Z' };
  h.post.mockReset().mockImplementation(async (path: string, body: { mode: string; after?: { id: string } }) => path === '/api/shop/catalogue/page' ? { ok: true, data: pageFixture(body) } : { ok: false, error: { code: 'network_failed', message: 'Try again.' } });
  screen = (await import('../../app/(member)/shop')).default;
});
describe('NAVC-008 catalogue-first native Shop', () => {
  it('renders Products, Plans and Services before purchase access and reservation history', async () => {
    await render(); const rendered = text();
    const productsAt = rendered.indexOf('Products'); const plansAt = rendered.indexOf('Plans'); const servicesAt = rendered.indexOf('Services');
    expect(productsAt).toBeGreaterThanOrEqual(0); expect(plansAt).toBeGreaterThan(productsAt); expect(servicesAt).toBeGreaterThan(plansAt);
    const purchase = action(/purchase requests|^Buy$/i); const purchaseAt = nodes.indexOf(purchase);
    const serviceAt = nodes.findIndex(node => ['children', 'title'].some(key => /Actual assessment service/.test(words(node.props[key]))));
    expect(purchaseAt).toBeGreaterThan(serviceAt); expect(rendered.indexOf('History reservation 1 sentinel')).toBeGreaterThan(servicesAt);
  });
  it('uses saved category names and Other products without inferring category from a product name', async () => {
    await render(); expect(text()).toContain('Recovery essentials'); expect(text()).toContain('Hydration'); expect(text()).toContain('Other products');
    expect(text()).toContain(item.name); expect(text().indexOf('Other products')).toBeLessThan(text().indexOf(item.name));
  });
  it('no-image long product retains its actual full name and honest image placeholder', async () => {
    await render(); expect(text()).toContain(item.name);
    expect(nodes.filter(node => node.type === 'Image' && node.props.source)).toHaveLength(0);
    await press(new RegExp(item.name)); expect(action(/^Reserve/i)).toBeDefined();
  });
  it('opens current Buy request management contextually', async () => {
    await render(); await press(/purchase requests|^Buy$/i);
    expect(h.push.mock.calls.some(([path]) => path === '/(member)/buy' || typeof path === 'object' && path.pathname === '/(member)/buy')).toBe(true);
  });
  it('renders three reservations, then five more per explicit tap without another catalogue fetch', async () => {
    await render(); expect(shownReservations()).toHaveLength(3); const reads = h.post.mock.calls.filter(([path, body]) => path === '/api/shop/catalogue/page' && body.mode === 'initial').length;
    await press(/^Load more$/i); expect(shownReservations()).toHaveLength(8); await press(/^Load more$/i); expect(shownReservations()).toHaveLength(11);
    expect(h.post.mock.calls.filter(([path, body]) => path === '/api/shop/catalogue/page' && body.mode === 'initial')).toHaveLength(reads);
    expect(h.post.mock.calls.filter(([path, body]) => path === '/api/shop/catalogue/page' && body.mode === 'more')).toHaveLength(1);
    expect(nodes.find(node => typeof node.props.onPress === 'function' && /^Load more$/i.test(words(node.props.children ?? node.props.title)))).toBeUndefined();
  });
  it('discloses the two hidden active holds and reaches their deadlines and cancellation controls', async () => {
    await render(); expect(shownReservations()).toHaveLength(3); expect(text()).toMatch(/2\s+(?:more\s+|additional\s+)?active\s+(?:holds|reservations)|(?:more|additional|hidden)\s+active\s+(?:holds|reservations)[^0-9]*2/i);
    await press(/^Load more$/i); expect(text()).toContain(reservations[3]!.itemName); expect(text()).toContain(reservations[4]!.itemName);
    expect(text()).toMatch(/2099|7 Oct|Oct 7/); expect(action(/Cancel/i)).toBeDefined();
  });
  it('six reservations reveal all remaining rows after one tap', async () => {
    catalogue = { ...catalogue, reservations: reservations.slice(0, 6) }; await render(); expect(shownReservations()).toHaveLength(3);
    await press(/^Load more$/i); expect(shownReservations()).toHaveLength(6);
  });
});
