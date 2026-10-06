import { beforeEach, describe, expect, it, vi } from 'vitest';
import { announcementPreview, businessNouns, UI_TOKENS } from '@gymloop/shared';

// Independent reference-layout tests. Fixtures and hook rendering derive from
// existing visible native suites; no Home/Shop/announcement/UI source was read.
type Node = { type: unknown; props: Record<string, unknown>; ancestors?: Node[] };
const h = vi.hoisted(() => ({
  cursor: 0, slots: [] as unknown[], effects: [] as Array<() => unknown>, changed: false,
  post: vi.fn(), push: vi.fn(), markRead: vi.fn(), scrollTo: vi.fn(), reloadPlans: vi.fn(),
}));
vi.mock('react', async original => {
  const actual = await original<Record<string, unknown>>();
  const memo = (factory: () => unknown, deps?: unknown[]) => {
    const index = h.cursor++;
    const old = h.slots[index] as { deps?: unknown[]; value: unknown } | undefined;
    if (!old || !deps || deps.some((value, offset) => !Object.is(value, old.deps?.[offset]))) h.slots[index] = { deps, value: factory() };
    return (h.slots[index] as { value: unknown }).value;
  };
  const hooks = {
    useState: (initial: unknown) => {
      const index = h.cursor++;
      if (!(index in h.slots)) h.slots[index] = typeof initial === 'function' ? initial() : initial;
      return [h.slots[index], (next: unknown) => {
        const value = typeof next === 'function' ? next(h.slots[index]) : next;
        if (!Object.is(value, h.slots[index])) { h.slots[index] = value; h.changed = true; }
      }];
    },
    useRef: (initial: unknown) => memo(() => ({ current: initial }), []),
    useMemo: memo, useCallback: (callback: unknown, deps?: unknown[]) => memo(() => callback, deps),
    useEffect: (effect: () => unknown, deps?: unknown[]) => memo(() => { h.effects.push(effect); return undefined; }, deps),
    useId: () => 'reference-layout', useTransition: () => [false, (run: () => unknown) => run()],
  };
  return { ...actual, ...hooks, default: { ...(actual.default as Record<string, unknown>), ...hooks } };
});
vi.mock('react-native', () => ({
  View: 'View', Text: 'Text', Pressable: 'Pressable', Image: 'Image', ScrollView: 'ScrollView', Modal: 'Modal',
  ActivityIndicator: 'ActivityIndicator', TextInput: 'TextInput', KeyboardAvoidingView: 'KeyboardAvoidingView',
  StyleSheet: { create: (styles: unknown) => styles, hairlineWidth: 1, absoluteFillObject: {}, flatten: (styles: unknown) => styles },
  Platform: { OS: 'android', select: (values: Record<string, unknown>) => values.android },
  Dimensions: { get: () => ({ width: 390, height: 844 }) }, useWindowDimensions: () => ({ width: 390, height: 844, scale: 1, fontScale: 1 }),
  useColorScheme: () => 'light', AppState: { currentState: 'active', addEventListener: () => ({ remove: vi.fn() }) },
  AccessibilityInfo: { announceForAccessibility: vi.fn(), isReduceMotionEnabled: async () => false, addEventListener: () => ({ remove: vi.fn() }) },
  // Both public scroll components mount the same imperative ScrollView host.
  Animated: { View: 'AnimatedView', ScrollView: 'ScrollView', event: () => vi.fn(), Value: class { interpolate() { return 0; } setValue() {} }, timing: () => ({ start: vi.fn(), stop: vi.fn() }), spring: () => ({ start: vi.fn(), stop: vi.fn() }), loop: () => ({ start: vi.fn(), stop: vi.fn() }), parallel: () => ({ start: vi.fn(), stop: vi.fn() }) },
  Easing: { linear: (value: unknown) => value, out: (value: unknown) => value, inOut: (value: unknown) => value, ease: (value: unknown) => value },
}));
vi.mock('react-native-safe-area-context', () => ({ SafeAreaView: 'SafeAreaView', useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }) }));
vi.mock('react-native-svg', () => ({ default: 'Svg', Svg: 'Svg', Path: 'Path', G: 'G', Circle: 'Circle', Rect: 'Rect', Defs: 'Defs', ClipPath: 'ClipPath', LinearGradient: 'LinearGradient', RadialGradient: 'RadialGradient', Stop: 'Stop' }));
vi.mock('lucide-react-native', () => new Proxy({}, { get: (_target, name) => name === 'then' ? undefined : String(name), has: () => true }));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: h.push, replace: vi.fn() }), useLocalSearchParams: () => ({}), Link: 'Link', Redirect: 'Redirect' }));
vi.mock('expo-network', () => ({ useNetworkState: () => ({ isConnected: true, isInternetReachable: true }), getNetworkStateAsync: async () => ({ isConnected: true, isInternetReachable: true }), addNetworkStateListener: () => ({ remove: vi.fn() }) }));
vi.mock('expo-secure-store', () => ({ getItemAsync: async () => null, setItemAsync: vi.fn(), deleteItemAsync: vi.fn() }));
vi.mock('expo-font', () => ({ useFonts: () => [true, null], isLoaded: () => true, loadAsync: async () => undefined }));
vi.mock('expo-haptics', () => ({ selectionAsync: async () => undefined, impactAsync: async () => undefined, notificationAsync: async () => undefined }));
vi.mock('expo-camera', () => ({ CameraView: 'CameraView', useCameraPermissions: () => [{ granted: false }, vi.fn()] }));
vi.mock('expo-crypto', () => ({ randomUUID: () => 'reference-event' }));
vi.mock('expo-web-browser', () => ({ openBrowserAsync: vi.fn() }));
vi.mock('../../../../packages/shared/assets/fonts/GoogleSans-Medium.ttf', () => ({ default: 'test-font' }));
vi.mock('../../lib/mobile-context', () => ({ useMobile: () => ({
  identity: { kind: 'member', userId: 'user-a', tenantId: 'tenant-a', memberId: 'member-a', role: 'member' },
  api: { post: h.post }, ready: true, nouns: businessNouns('gym'), palette: UI_TOKENS.colors.light,
  businessType: 'gym', appearance: 'light', supabase: {}, session: { user: { email: 'member@example.test' } }, signOut: vi.fn(),
}) }));
vi.mock('../../lib/use-member-snapshot', () => ({ useMemberSnapshot: () => ({ data: snapshot, error: null, loading: false, reload: vi.fn() }) }));
vi.mock('../../lib/use-member-plans', () => ({ useMemberPlans: () => ({ state: {
  phase: 'ready', view: { plans: [{ id: 'plan-a', name: 'Current monthly catalogue plan', description: null, durationDays: 30, pricePaise: '150000', currency: 'INR', gstRateBp: 0, held: false }], truncated: false, heldUnavailable: false, held: null },
  loadedAt: null, staleReason: null, offline: false,
}, reload: h.reloadPlans }) }));
vi.mock('../../lib/use-announcements', () => ({ useAnnouncements: () => feed }));
vi.mock('../../lib/offline-check-in', () => ({ saveOfflineCheckIn: vi.fn(), loadOfflineCheckIns: async () => [], clearOfflineCheckIns: vi.fn(), shouldReplayOnSignal: () => false, createReplayCoordinator: () => ({ requestReplay: vi.fn() }) }));
// Keep real native controls and Screen behavior, capturing only their public
// props. The ScrollView host mounts imperative refs exactly at the host seam.
vi.mock('../../components/ui', async original => {
  const actual = await original<Record<string, unknown>>();
  const capture = (type: string) => (props: Record<string, unknown>) => ({ type, props: {
    ...props, rendered: (actual[type] as (props: Record<string, unknown>) => unknown)(props),
  } });
  return { ...actual, Screen: capture('Screen'), Display: capture('Display'), RowAction: capture('RowAction'), ActionButton: capture('ActionButton') };
});
const snapshot = {
  member: { fullName: 'Aarav Sharma', memberCode: 'LAYOUT-101', email: 'member@example.test', phone: '+917000000101', goal: 5, restDays: [] },
  gym: { name: 'Fixture Gym', displayName: 'Fixture Gym', timezone: 'Asia/Kolkata', city: 'Mumbai', state: null, branchName: 'Main', branchAddress: null },
  membership: { status: 'active', startsOn: '2026-10-01', endsOn: '2026-10-31', planName: 'Monthly' },
  visits: [{ id: 'visit-a', checkedInAt: '2026-10-05T06:00:00Z', source: 'qr' }], weekVisits: 4, weekStart: '2026-10-05',
  streak: { current: 1, unit: 'week', missed: [] }, receipts: [], addOns: [], consents: [],
  messages: [{ id: 'personal-a', body: 'Personal latest membership invitation', sentAt: '2026-10-05T06:00:00Z', status: 'sent' }, { id: 'personal-b', body: 'Personal older membership invitation', sentAt: '2026-10-04T06:00:00Z', status: 'sent' }],
};
const cards = ['First shared closure', 'Second shared event', 'Third unseen shared update'].map((title, index) => ({
  announcementId: `75000000-0000-4000-8000-${String(index + 701).padStart(12, '0')}`, title,
  body: `${title}: ${'Please read the complete details before attending. '.repeat(8)}Full body final sentinel ${index}.`,
  kind: 'transactional' as const, imageUrl: null, versionNo: 1, publishedAt: '2026-10-05T00:00:00Z',
  editedAt: null, expiresAt: null, changeNote: null, readState: 'unread' as const, readAt: null,
}));
const feed = { cards, loading: false, stale: false, error: null, fetchedAt: null, reload: vi.fn(async () => undefined), markRead: h.markRead };
const product = { itemId: '72000000-0000-4000-8000-000000000701', section: 'products', name: 'Complete long recovery product catalogue name', description: 'Actual product description', pricePaise: '199900', currency: 'INR', gstRateBp: 0, validityDays: 30, cancellationTerms: 'Ask desk', quoteVersion: '72000000-0000-4000-8000-000000000799', categoryId: '72000000-0000-4000-8000-000000000711', categoryName: 'Recovery essentials', imageUrl: null, availability: 'available', availableQuantity: 2 };
const reservations = Array.from({ length: 11 }, (_, index) => ({
  reservationId: `72000000-0000-4000-8000-${String(index + 800).padStart(12, '0')}`, itemId: product.itemId, itemName: `Existing reservation ${index + 1} sentinel`, section: 'products',
  quantity: 1, unitPricePaise: '199900', totalPaise: '199900', currency: 'INR', state: 'reserved',
  createdAt: '2026-10-06T04:30:00Z', expiresAt: '2099-10-07T04:30:00Z', cancelReason: null, termsChanged: false, orderId: null, imageUrl: null,
}));
const catalogue = { items: [product, { ...product, itemId: '72000000-0000-4000-8000-000000000702', section: 'services', name: 'Actual assessment service' }], reservations, truncated: false, serverTime: '2026-10-06T04:30:00Z' };
let screen: () => unknown;
let nodes: Node[] = [];
function flatten(value: unknown, ancestors: Node[] = []): void {
  if (Array.isArray(value)) { value.forEach(child => flatten(child, ancestors)); return; }
  if (!value || typeof value !== 'object' || !('props' in value)) return;
  const node = { ...(value as Node), ancestors };
  if (typeof node.type === 'function') { flatten(node.type(node.props), ancestors); return; }
  nodes.push(node);
  if (node.type === 'ScrollView' && node.props.ref) {
    const ref = node.props.ref as { current: unknown } | ((value: unknown) => void);
    const instance = { scrollTo: h.scrollTo };
    if (typeof ref === 'function') ref(instance); else ref.current = instance;
  }
  const next = [...ancestors, node];
  if ('rendered' in node.props) flatten(node.props.rendered, next);
  else { flatten(node.props.children, next); flatten(node.props.footer, next); flatten(node.props.trailing, next); }
}
async function render() {
  for (let pass = 0; pass < 30; pass++) {
    h.cursor = 0; h.changed = false; nodes = []; flatten(screen());
    for (const effect of h.effects.splice(0)) await effect();
    await new Promise(resolve => setTimeout(resolve, 0));
    if (!h.changed && h.effects.length === 0) return;
  }
  throw new Error('Reference-layout screen did not settle');
}
function words(value: unknown): string {
  if (typeof value === 'string' || typeof value === 'number') return String(value);
  if (Array.isArray(value)) return value.map(words).join(' ');
  return '';
}
function labels(node: Node): string[] { return ['children', 'title', 'meta', 'detail', 'message', 'label', 'accessibilityLabel'].map(key => words(node.props[key]).trim()); }
function text(): string { return nodes.flatMap(labels).join(' ').replace(/\s+/g, ' '); }
function action(label: RegExp): Node {
  const node = nodes.find(node => typeof node.props.onPress === 'function' && labels(node).some(value => label.test(value)));
  expect(node, `native action ${label}`).toBeDefined(); return node!;
}
async function press(label: RegExp) { await (action(label).props.onPress as () => unknown)(); await render(); }
async function mount(route: 'shop' | 'home' | 'announcements') {
  h.slots = []; h.cursor = 0; h.effects = [];
  screen = route === 'shop' ? (await import('../(member)/shop')).default
    : route === 'home' ? (await import('../(member)/index')).default : (await import('../(member)/announcements')).default;
  await render();
}
function shownReservations() { return reservations.filter(row => text().includes(row.itemName)); }
async function measureSection(label: string, y: number) {
  const heading = nodes.find(node => typeof node.props.onPress !== 'function'
    && node.ancestors?.every(parent => typeof parent.props.onPress !== 'function') && labels(node).some(value => value === label));
  expect(heading, `${label} section heading`).toBeDefined();
  const anchor = [...(heading?.ancestors ?? []), heading!].reverse().find(node => typeof node.props.onLayout === 'function');
  expect(anchor, `${label} measured section`).toBeDefined();
  (anchor!.props.onLayout as (event: unknown) => void)({ nativeEvent: { layout: { x: 0, y, width: 390, height: 180 } } });
  await render();
}
beforeEach(() => {
  vi.resetModules(); h.slots = []; h.cursor = 0; h.effects = []; h.changed = false;
  h.push.mockReset(); h.scrollTo.mockReset(); h.markRead.mockReset().mockResolvedValue(undefined); h.reloadPlans.mockReset().mockResolvedValue(undefined);
  h.post.mockReset().mockImplementation(async (path: string) => path === '/api/shop/catalogue' ? { ok: true, data: catalogue } : { ok: false, error: { code: 'network_failed', message: 'Try again.' } });
});
describe('NAVC-008/012 approved Shop section links', () => {
  it.each([['Products', 157], ['Plans', 607], ['Services', 1179]] as const)('%s reaches its measured position in the existing scroll column', async (label, y) => {
    await mount('shop'); const link = action(new RegExp(`^${label}$`));
    expect(link.type).toBe('RowAction');
    await measureSection(label, y); await press(new RegExp(`^${label}$`));
    expect(h.scrollTo).toHaveBeenLastCalledWith(expect.objectContaining({ y, animated: true }));
    const updatedY = y + 83; await measureSection(label, updatedY); await press(new RegExp(`^${label}$`));
    expect(h.scrollTo).toHaveBeenLastCalledWith(expect.objectContaining({ y: updatedY }));
  });
  it('repeated section taps retain all catalogue sections and 3/+5 disclosure without reading or navigating', async () => {
    await mount('shop'); expect(shownReservations()).toHaveLength(3);
    expect(text()).toMatch(/8\s+(?:more\s+|additional\s+)?active\s+(?:holds|reservations)|(?:more|additional|hidden)\s+active\s+(?:holds|reservations)[^0-9]*8/i);
    const reads = h.post.mock.calls.length;
    for (const label of ['Services', 'Plans', 'Products', 'Services', 'Products']) await press(new RegExp(`^${label}$`));
    expect(h.post).toHaveBeenCalledTimes(reads); expect(h.reloadPlans).not.toHaveBeenCalled(); expect(h.push).not.toHaveBeenCalled();
    expect(text()).toContain(product.name); expect(text()).toContain('Recovery essentials'); expect(text()).toContain('Current monthly catalogue plan'); expect(text()).toContain('Actual assessment service');
    expect(shownReservations()).toHaveLength(3);
    await press(/^Load more$/i); expect(shownReservations()).toHaveLength(8);
    await press(/^Load more$/i); expect(shownReservations()).toHaveLength(11);
    expect(h.post).toHaveBeenCalledTimes(reads); expect(action(/Cancel/i)).toBeDefined(); expect(text()).toMatch(/2099|7 Oct|Oct 7/);
  });
  it('Refresh shop stays a compact accessible action with its existing refresh behavior', async () => {
    await mount('shop'); const refresh = action(/^Refresh shop$/i);
    expect(refresh.type).toBe('RowAction');
    const button = nodes.find(node => node.type === 'Pressable' && node.ancestors?.includes(refresh));
    expect(button?.props.accessibilityRole).toBe('button');
    const reads = h.post.mock.calls.filter(([path]) => path === '/api/shop/catalogue').length;
    await press(/^Refresh shop$/i);
    expect(h.post.mock.calls.filter(([path]) => path === '/api/shop/catalogue')).toHaveLength(reads + 1);
  });
});
describe('NAVC-009/012 approved compact Home', () => {
  it('weekly visits use the existing accented metric Display without a hero figure', async () => {
    await mount('home');
    const figure = nodes.find(node => node.type === 'Display' && new RegExp(`^${snapshot.weekVisits}(?:\\s|$)`).test(words(node.props.children)));
    expect(figure, 'weekly-visit Display').toBeDefined();
    expect(figure?.props.size).toBe('metric'); expect(figure?.props.accent).toBe(true);
    expect(nodes.filter(node => node.type === 'Display' && node.props.size === 'hero')).toHaveLength(0);
  });
  it('keeps one personal preview, two shared updates after Last visit, and one visible body line', async () => {
    await mount('home'); const rendered = text();
    expect(rendered).toContain(snapshot.messages[0]!.body); expect(rendered).not.toContain(snapshot.messages[1]!.body);
    expect(nodes.filter(node => labels(node).includes('Messages for you'))).toHaveLength(1);
    expect(rendered.indexOf('Messages for you')).toBeLessThan(rendered.indexOf('Last visit'));
    expect(rendered.indexOf('Last visit')).toBeLessThan(rendered.indexOf(cards[0]!.title));
    expect(rendered).toContain(cards[1]!.title); expect(rendered).not.toContain(cards[2]!.title);
    for (const card of cards.slice(0, 2)) {
      const preview = nodes.find(node => node.type === 'Text' && words(node.props.children) === announcementPreview(card.body));
      expect(preview, `${card.title} body preview`).toBeDefined(); expect(preview?.props.numberOfLines).toBe(1);
    }
    expect(nodes.some(node => /bell/i.test(String(node.type)))).toBe(false); expect(h.markRead).not.toHaveBeenCalled();
  });
  it('opening a compact shared update retains its complete body and exact version receipt', async () => {
    await mount('home'); await press(new RegExp(cards[0]!.title));
    expect(text()).toContain(cards[0]!.body.replace(/\s+/g, ' '));
    expect(h.markRead).toHaveBeenCalledWith(cards[0]!.announcementId, cards[0]!.versionNo);
    expect(h.markRead).not.toHaveBeenCalledWith(cards[2]!.announcementId, cards[2]!.versionNo);
  });
  it('View all retains separate full-list access and complete opened text without acknowledging unseen cards', async () => {
    await mount('home'); await press(/^View all$/i);
    expect(h.push.mock.calls.some(([path]) => path === '/(member)/announcements' || typeof path === 'object' && path.pathname === '/(member)/announcements')).toBe(true);
    expect(h.markRead).not.toHaveBeenCalled(); await mount('announcements');
    cards.forEach(card => expect(text()).toContain(card.title)); expect(h.markRead).not.toHaveBeenCalled();
    await press(new RegExp(cards[2]!.title)); expect(text()).toContain(cards[2]!.body.replace(/\s+/g, ' '));
    expect(h.markRead).toHaveBeenCalledWith(cards[2]!.announcementId, cards[2]!.versionNo);
  });
});
describe('NAVC existing Screen optional scroll-ref seam', () => {
  it('mounts the supplied ref on the existing native scroll column and keeps ordinary callers working', async () => {
    const { Screen } = await import('../../components/ui'); const scrollRef = { current: null as unknown };
    screen = () => Screen({ scrollRef, children: 'Ref caller content' } as Parameters<typeof Screen>[0]); await render();
    expect(scrollRef.current).toEqual(expect.objectContaining({ scrollTo: h.scrollTo }));
    expect(nodes.filter(node => node.type === 'ScrollView')).toHaveLength(1);
    h.slots = []; screen = () => Screen({ children: 'Ordinary caller content' }); await render();
    expect(text()).toContain('Ordinary caller content'); expect(nodes.filter(node => node.type === 'ScrollView')).toHaveLength(1);
  });
});
