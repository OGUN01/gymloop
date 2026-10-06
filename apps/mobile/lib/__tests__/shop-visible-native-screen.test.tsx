import { beforeEach, describe, expect, it, vi } from 'vitest';

// Test-only React/native boundary. This renders the actual screen and runs its
// hooks; all catalogue, cache and command decisions remain in the real modules.
type Node = { type: unknown; props: Record<string, unknown> };
const h = vi.hoisted(() => ({ cursor: 0, slots: [] as unknown[], effects: [] as Array<() => unknown>, changed: false, online: true, identity: { kind: 'member', userId: 'user-a', tenantId: 'tenant-a', memberId: 'member-a', role: 'member' } as Record<string, string>, post: vi.fn(), queue: vi.fn(), persist: vi.fn() }));
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
vi.mock('../mobile-context', () => ({ useMobile: () => ({ identity: h.identity, api: { post: h.post }, ready: true, nouns: { place: 'gym', plural: 'gyms', member: 'member', trainer: 'trainer', class: 'class' }, palette: {}, businessType: 'gym', appearance: 'light', supabase: {}, session: h.identity.kind === 'member' ? {} : null, signOut: vi.fn() }) }));
vi.mock('../use-member-snapshot', () => ({ useMemberSnapshot: () => ({ data: { gym: { name: 'Fixture Gym', displayName: 'Fixture Gym', timezone: 'Asia/Kolkata' } }, error: null, loading: false, reload: vi.fn() }) }));
// NAVC-008 adds plans before Shop offers. Isolate PLC's registered read seam;
// the actual Shop catalogue, cache, identity and command paths remain exercised.
vi.mock('../use-member-plans', () => ({ useMemberPlans: () => ({ state: { phase: 'idle', view: null, loadedAt: null, staleReason: null, offline: false }, reload: async () => undefined }) }));
vi.mock('expo-network', () => ({ useNetworkState: () => ({ isConnected: h.online, isInternetReachable: h.online }), getNetworkStateAsync: async () => ({ isConnected: h.online, isInternetReachable: h.online }), addNetworkStateListener: () => ({ remove: vi.fn() }) }));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: vi.fn(), replace: vi.fn() }), useLocalSearchParams: () => ({}), Link: 'Link', Redirect: 'Redirect' }));
vi.mock('expo-secure-store', () => ({ setItemAsync: h.persist, getItemAsync: async () => null, deleteItemAsync: vi.fn() }));
vi.mock('../offline-check-in', () => ({ saveOfflineCheckIn: h.queue, loadOfflineCheckIns: async () => [], clearOfflineCheckIns: vi.fn(), shouldReplayOnSignal: () => false, createReplayCoordinator: () => ({ requestReplay: vi.fn() }) }));
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', Image: 'Image', ScrollView: 'ScrollView', Modal: 'Modal', ActivityIndicator: 'ActivityIndicator', TextInput: 'TextInput', StyleSheet: { create: (styles: unknown) => styles }, AppState: { addEventListener: () => ({ remove: vi.fn() }) }, useColorScheme: () => 'light' }));
vi.mock('lucide-react-native', () => ({ ShoppingBag: 'ShoppingBag', Package: 'Package', Image: 'ImageIcon', ImageOff: 'ImageOff', Plus: 'Plus', Minus: 'Minus', RefreshCw: 'RefreshCw', X: 'X', ChevronRight: 'ChevronRight', Check: 'Check', Clock: 'Clock' }));
vi.mock('../../components/ui', () => {
  const widgets = ['Screen', 'Eyebrow', 'Title', 'Display', 'Body', 'Rule', 'Status', 'Row', 'LedgerSection', 'SheetHeader', 'ActionButton', 'RowAction', 'StateMessage', 'EmptyState', 'LoadingState', 'Field', 'ChoiceList'];
  return { ...Object.fromEntries(widgets.map(type => [type, (props: Record<string, unknown>) => ({ type, props })])), Sheet: (props: Record<string, unknown>) => props.visible ? { type: 'Sheet', props } : null };
});
const id = '72000000-0000-4000-8000-000000000001';
const item = { itemId: id, section: 'products', name: 'Visible native protein', description: 'Tub', pricePaise: '199900', currency: 'INR', gstRateBp: 0, validityDays: 30, cancellationTerms: 'Ask desk', quoteVersion: id, categoryId: null, categoryName: null, imageUrl: null, availability: 'available', availableQuantity: 2 };
const reservation = { reservationId: id, itemId: id, itemName: 'Visible reserved protein', section: 'products', quantity: 1, unitPricePaise: '199900', totalPaise: '199900', currency: 'INR', state: 'reserved', createdAt: '2026-10-02T04:30:00Z', expiresAt: '2099-10-03T04:30:00Z', cancelReason: null, termsChanged: false, orderId: null, imageUrl: null };
const catalogue = { items: [item], reservations: [reservation], truncated: false, serverTime: '2026-10-02T04:30:00Z' };
let screen: () => unknown;
let nodes: Node[];
function flatten(value: unknown): void {
  if (Array.isArray(value)) { value.forEach(flatten); return; }
  if (!value || typeof value !== 'object' || !('props' in value)) return;
  const node = value as Node;
  if (typeof node.type === 'function') { flatten(node.type(node.props)); return; }
  nodes.push(node); flatten(node.props.children); flatten(node.props.footer); flatten(node.props.trailing);
}
async function render() {
  for (let pass = 0; pass < 30; pass++) {
    h.cursor = 0; h.changed = false; nodes = []; flatten(screen());
    const effects = h.effects.splice(0); effects.forEach(effect => effect());
    await new Promise(resolve => setTimeout(resolve, 0));
    if (!h.changed && h.effects.length === 0) return;
  }
  throw new Error('Screen did not settle');
}
function text() { return JSON.stringify(nodes.map(node => node.props)); }
function action(label: RegExp) {
  const node = nodes.find(node => typeof node.props.onPress === 'function' && label.test(String(node.props.children ?? node.props.title ?? node.props.accessibilityLabel ?? '')));
  expect(node, `Missing actual screen control ${label}`).toBeDefined(); return node!;
}
beforeEach(async () => {
  vi.resetModules(); h.cursor = 0; h.slots = []; h.effects = []; h.changed = false; h.online = true; h.identity = { kind: 'member', userId: 'user-a', tenantId: 'tenant-a', memberId: 'member-a', role: 'member' };
  h.post.mockReset().mockImplementation(async (path: string) => h.online && path === '/api/shop/catalogue' ? { ok: true, data: catalogue } : { ok: false, error: { code: 'network_failed', message: "That didn't go through. Try again." } }); h.queue.mockReset(); h.persist.mockReset();
});
describe('native React runtime harness control', () => {
  it('mobile-resolved named and default hooks use the test renderer state and effects', async () => {
    const runtime = await import('react') as typeof import('react') & { default: typeof import('react') };
    const effect = vi.fn(); const marker = {};
    const probe = () => {
      const [value, setValue] = runtime.useState('initial');
      const memo = runtime.default.useMemo(() => marker, []);
      runtime.useEffect(effect, []);
      return { value, setValue, memo };
    };
    const first = probe(); expect(first.value).toBe('initial'); expect(first.memo).toBe(marker); expect(h.cursor).toBe(3);
    expect(h.effects).toHaveLength(1); h.effects.splice(0).forEach(callback => callback()); expect(effect).toHaveBeenCalledTimes(1);
    first.setValue('updated'); expect(h.changed).toBe(true); h.cursor = 0;
    const second = probe(); expect(second.value).toBe('updated'); expect(second.memo).toBe(marker); expect(h.effects).toHaveLength(0);
  });
});
describe('SHP-022 actual native Shop screen offline contract', () => {
  beforeEach(async () => { screen = (await import('../../app/(member)/shop')).default; });
  it.each([[/Reserve/i, item.name], [/Cancel/i, reservation.itemName]] as const)('shows last-good data and refuses %s offline without a queue', async (label, title) => {
    await render(); expect(text()).toContain(item.name); expect(text()).toContain(reservation.itemName);
    if (!nodes.some(node => typeof node.props.onPress === 'function' && label.test(String(node.props.children ?? node.props.title ?? node.props.accessibilityLabel ?? '')))) {
      await (action(new RegExp(title)).props.onPress as () => unknown)(); await render();
    }
    expect(action(label)).toBeDefined();
    h.online = false; await render(); expect(text()).toMatch(/offline/i); expect(text()).toMatch(/saved/i);
    const callsBefore = h.post.mock.calls.length;
    // Even invoking a stale/native handler directly must not send or enqueue.
    const control = action(label); expect(control.props.disabled ?? (control.props.accessibilityState as { disabled?: boolean })?.disabled).toBe(true);
    await (control.props.onPress as () => unknown)(); await render();
    expect(h.post.mock.calls.slice(callsBefore).filter(([path]) => /reservations/.test(path))).toEqual([]); expect(h.queue).not.toHaveBeenCalled(); expect(h.persist).not.toHaveBeenCalled(); expect(text()).not.toMatch(/successfully reserved|successfully cancelled/i);
  });
  it.each(['tenantId', 'memberId', 'userId'])('identity change in %s never exposes the previous saved catalogue', async field => {
    await render(); expect(text()).toContain(item.name); const original = h.identity; h.online = false; h.identity = { ...h.identity, [field]: 'changed-identity' }; await render(); expect(text()).not.toContain(item.name); expect(text()).not.toContain(reservation.itemName);
    h.identity = original; await render(); expect(text()).not.toContain(item.name); expect(text()).not.toContain(reservation.itemName);
  });
  it('sign-out clears the last-good view rather than retaining member data', async () => {
    await render(); expect(text()).toContain(item.name); const original = h.identity; h.identity = { kind: 'unlinked' }; h.online = false; await render(); expect(text()).not.toContain(item.name); expect(text()).not.toContain(reservation.itemName); expect(h.queue).not.toHaveBeenCalled();
    h.identity = original; await render(); expect(text()).not.toContain(item.name); expect(text()).not.toContain(reservation.itemName);
  });
});
