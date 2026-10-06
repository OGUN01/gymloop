import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, isValidElement, type ReactElement, type ReactNode } from 'react';
import { UI_TOKENS } from '@gymloop/shared';

// Fixture fields come only from pre-existing exported MemberSnapshot and the
// inferred public useMemberSnapshot return signature (no component bodies read).
const { state } = vi.hoisted(() => ({ state: {
  type: 'dance' as 'dance' | 'gym' | 'yoga' | 'martial_arts' | 'studio', slots: [] as unknown[], cursor: 0,
  effects: [] as Array<() => unknown>, error: false, loading: false,
  empty: false, desk: false, trainer: false, count: 1, section: undefined as string | string[] | undefined, push: vi.fn(), browser: vi.fn(), plans: vi.fn(),
} }));
const nouns = {
  yoga: { place: 'studio', session: 'class', sessions: 'classes', class: 'class', classes: 'classes', member: 'member', members: 'members', trainer: 'teacher' },
  martial_arts: { place: 'academy', session: 'class', sessions: 'classes', class: 'class', classes: 'classes', member: 'student', members: 'students', trainer: 'instructor' },
  studio: { place: 'studio', session: 'session', sessions: 'sessions', class: 'class', classes: 'classes', member: 'member', members: 'members', trainer: 'trainer' },
  dance: { place: 'academy', session: 'class', sessions: 'classes', class: 'batch', classes: 'batches', member: 'student', members: 'students', trainer: 'instructor' },
  gym: { place: 'gym', session: 'session', sessions: 'sessions', class: 'class', classes: 'classes', member: 'member', members: 'members', trainer: 'trainer' },
};
function snapshot() {
  return {
    member: { fullName: 'Aarav Sharma', memberCode: 'BIZ-101', email: 'aarav@example.test', phone: '+917000000101', goal: 3, restDays: [] },
    gym: { name: 'IA Fitness', displayName: 'IA Fitness', code: 'BIZ70A', timezone: 'Asia/Kolkata', city: 'Mumbai', state: null, branchName: 'Main', branchAddress: null },
    membership: { status: 'active', startsOn: '2026-10-01', endsOn: '2026-10-31', planName: 'Monthly' },
    visits: state.empty ? [] : [{ id: 'v1', checkedInAt: '2026-10-01T06:00:00Z', source: 'qr' }],
    weekVisits: 1, weekStart: '2026-09-28', streak: { current: 1, unit: 'week', missed: [] }, receipts: [],
    messages: [{ id: 'note', body: 'Personal newest invitation', sentAt: '2026-10-02T06:00:00Z', status: 'sent' }, { id: 'old-note', body: 'Personal older invitation', sentAt: '2026-10-01T06:00:00Z', status: 'sent' }], consents: [],
    addOns: [{ id: 'pack', name: 'Movement pack', status: 'active', totalPaise: '9007199254740993', currency: 'INR', sessionsUsed: 1, sessionsTotal: 3 }],
  };
}
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
  View: host('view'), Text: host('text'), Pressable: host('button'), TextInput: host('input'), ScrollView: host('scroll'), Image: host('image'), Modal: host('modal'), ActivityIndicator: host('loading'), KeyboardAvoidingView: host('keyboard'),
  StyleSheet: { create: (value: unknown) => value, hairlineWidth: 1, absoluteFillObject: {}, flatten: (value: unknown) => value },
  Platform: { OS: 'android', select: (value: Record<string, unknown>) => value.android },
  Linking: { openURL: async () => undefined }, Dimensions: { get: () => ({ width: 390, height: 844 }) }, useWindowDimensions: () => ({ width: 390, height: 844, fontScale: 1, scale: 1 }),
  useColorScheme: () => 'light', AccessibilityInfo: { announceForAccessibility: () => undefined, isReduceMotionEnabled: async () => false, addEventListener: () => ({ remove: () => undefined }) },
  AppState: { currentState: 'active', addEventListener: () => ({ remove: () => undefined }) },
  Animated: { View: host('animated-view'), ScrollView: host('animated-scroll'), event: () => () => undefined, Value: class { value: number; constructor(value: number) { this.value = value; } interpolate() { return 0; } setValue() {} }, timing: () => ({ start: () => undefined, stop: () => undefined }), spring: () => ({ start: () => undefined, stop: () => undefined }), loop: () => ({ start: () => undefined, stop: () => undefined }), parallel: () => ({ start: () => undefined, stop: () => undefined }) },
  Easing: { linear: (value: number) => value, out: (value: unknown) => value, inOut: (value: unknown) => value, ease: (value: number) => value },
}));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: state.push, replace: vi.fn() }), useLocalSearchParams: () => ({ section: state.section }), Tabs: Object.assign(host('tabs'), { Screen: host('tab') }), Link: host('link') }));
vi.mock('expo-camera', () => ({ CameraView: host('camera'), useCameraPermissions: () => [{ granted: false }, vi.fn()] }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: async () => ({ isConnected: false }), addNetworkStateListener: () => ({ remove: () => undefined }) }));
vi.mock('expo-crypto', () => ({ randomUUID: () => 'event' }));
vi.mock('expo-haptics', () => ({ selectionAsync: async () => undefined, impactAsync: async () => undefined, notificationAsync: async () => undefined }));
vi.mock('expo-web-browser', () => ({ openBrowserAsync: state.browser }));
vi.mock('expo-secure-store', () => ({ getItemAsync: async () => null, setItemAsync: async () => undefined, deleteItemAsync: async () => undefined }));
vi.mock('expo-font', () => ({ useFonts: () => [true, null], isLoaded: () => true, loadAsync: async () => undefined }));
vi.mock('../../../../packages/shared/assets/fonts/GoogleSans-Medium.ttf', () => ({ default: 'test-font' }));
vi.mock('react-native-svg', () => ({ default: host('svg'), Svg: host('svg'), Path: host('path'), G: host('g'), Circle: host('circle'), Rect: host('rect'), Defs: host('defs'), ClipPath: host('clipPath'), LinearGradient: host('linearGradient'), RadialGradient: host('radialGradient'), Stop: host('stop') }));
vi.mock('react-native-safe-area-context', () => ({ SafeAreaView: host('safe-area'), useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }) }));
vi.mock('lucide-react-native', () => new Proxy({}, { get: (_target, name) => name === 'then' ? undefined : host(String(name)), has: () => true }));
vi.mock('../../lib/mobile-context', () => ({ useMobile: () => ({
  identity: state.desk ? { kind: 'staff', tenantId: 't1', staffId: 's1', userId: 'u1', role: state.trainer ? 'trainer' : 'front_desk' } : { kind: 'member', tenantId: 't1', memberId: 'm1', userId: 'u1' },
  session: { user: { email: 'aarav@example.test' } }, supabase: {}, api: { post: vi.fn() }, palette: UI_TOKENS.colors.light,
  businessType: state.type, nouns: nouns[state.type], appearance: 'system', setAppearance: vi.fn(), signOut: vi.fn(), webOrigin: 'https://app.example',
}) }));
vi.mock('../../lib/use-member-snapshot', () => ({ useMemberSnapshot: () => ({ data: state.error ? null : snapshot(), error: null, loading: state.loading, reload: vi.fn() }) }));
// BIZ observes the real place screen with the PLC disclosure closed. Double
// only PLC's documented hook seam; its behavior has independent PLC coverage.
vi.mock('../../lib/use-member-plans', () => ({ useMemberPlans: (enabled: boolean) => { state.plans(enabled); return ({
  state: { phase: 'idle', view: null, loadedAt: null, staleReason: null, offline: false },
  reload: async () => undefined,
}); } }));
vi.mock('../../lib/mobile-data', async (original) => ({ ...await original<Record<string, unknown>>(),
  loadDeskMembers: async () => state.empty ? [] : Array.from({ length: state.count }, (_, index) => ({ id: `m${index}`, fullName: `Aarav Sharma ${index}`, phone: '+917000000101', status: 'active', memberCode: `BIZ-10${index}` })),
  loadDeskFollowUps: async () => [], loadDefaultBranch: async () => 'branch1',
}));
vi.mock('../../lib/offline-check-in', () => ({ loadOfflineCheckIns: async () => [], drainOfflineCheckIns: async () => [], saveOfflineCheckIn: vi.fn(), shouldReplayOnSignal: () => false, createReplayCoordinator: () => ({ requestReplay: vi.fn() }) }));

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
const routes = { home: () => import('../(member)/index'), gym: () => import('../(member)/gym'), you: () => import('../(member)/you'), classes: () => import('../(member)/classes'), more: () => import('../(desk)/more'), announcements: () => import('../(member)/announcements') };
let mountedRoute: keyof typeof routes | null = null;
async function render(name: keyof typeof routes) {
  if (mountedRoute !== name) { state.slots = []; state.cursor = 0; state.effects = []; mountedRoute = name; }
  state.desk = name === 'more';
  const Screen = (await routes[name]()).default;
  let tree: ReactNode;
  for (let pass = 0; pass < 6; pass += 1) {
    state.cursor = 0; tree = expand(createElement(Screen));
    for (const effect of state.effects.splice(0)) await effect();
    for (let tick = 0; tick < 8; tick += 1) await Promise.resolve();
  }
  return tree;
}
beforeEach(() => { state.type = 'gym'; state.slots = []; state.cursor = 0; state.effects = []; state.error = false; state.loading = false; state.empty = false; state.desk = false; state.trainer = false; state.section = undefined; state.push.mockClear(); state.browser.mockClear(); state.plans.mockClear(); });
beforeEach(() => { mountedRoute = null; });
vi.mock('../../components/classes-pane', () => ({ ClassesPane: (props: Record<string, unknown>) => createElement('classes-pane', props) }));
vi.mock('../../components/training-section', () => ({ TrainingSection: () => createElement('training-section') }));
vi.mock('../../lib/use-announcements', () => ({ useAnnouncements: () => feed }));

function press(tree: ReactNode, label: RegExp) {
  const found = nodes(tree).filter(node => typeof node.props.onPress === 'function' && [text(node), String(node.props.accessibilityLabel ?? '')].some(candidate => label.test(candidate.trim())));
  expect(found.length, `action ${label}`).toBeGreaterThan(0);
  (found[0]!.props.onPress as () => void)();
}
// NAVC-009 fixed three distinct shared cards and two personal notes make the
// preview limits and document order observable through rendered text.
const cards = [
  { announcementId: '75000000-0000-4000-8000-000000000701', title: 'Shared first closure', body: 'First shared notice body' },
  { announcementId: '75000000-0000-4000-8000-000000000702', title: 'Shared second event', body: 'Second shared notice body' },
  { announcementId: '75000000-0000-4000-8000-000000000703', title: 'Shared unseen third', body: 'Third shared notice body' },
].map(card => ({ ...card, kind: 'transactional' as const, imageUrl: null, versionNo: 1, publishedAt: '2026-10-02T00:00:00Z', editedAt: null, expiresAt: null, changeNote: null, readState: 'unread' as const, readAt: null }));
const feed = { cards, loading: false, stale: false, error: null, fetchedAt: null, reload: vi.fn(async () => undefined), markRead: vi.fn(async () => undefined) };
beforeEach(() => { feed.markRead.mockClear(); feed.reload.mockClear(); });
function destination(pathname: string, section?: string) {
  return state.push.mock.calls.some(([path]) => section
    ? typeof path === 'object' && path.pathname === pathname && path.params?.section === section || path === `${pathname}?section=${section}`
    : path === pathname || typeof path === 'object' && path.pathname === pathname);
}
describe('NAVC compact Home and contextual actions', () => {
  it('shows one personal preview near membership and two shared cards below Last visit', async () => {
    const tree = await render('home'); const rendered = text(tree);
    expect(rendered).toMatch(/Messages for you/); expect(rendered).toContain('Personal newest invitation'); expect(rendered).not.toContain('Personal older invitation');
    expect(rendered).toContain(cards[0]!.title); expect(rendered).toContain(cards[1]!.title); expect(rendered).not.toContain(cards[2]!.title);
    expect(rendered.indexOf('Messages for you')).toBeLessThan(rendered.indexOf('Last visit'));
    expect(rendered.indexOf('Last visit')).toBeLessThan(rendered.indexOf(cards[0]!.title));
    expect(rendered.match(/Messages for you/g)).toHaveLength(1);
    expect(nodes(tree).some(node => /bell/i.test(String(node.type)))).toBe(false);
  });
  it('personal preview opens the business-hub messages section', async () => {
    const tree = await render('home'); press(tree, /Messages for you|Personal newest invitation/i);
    expect(destination('/(member)/gym', 'messages')).toBe(true);
  });
  it('View all opens the separate announcement route without marking unseen cards read', async () => {
    const tree = await render('home'); expect(feed.markRead).not.toHaveBeenCalled(); press(tree, /^View all$/i);
    expect(destination('/(member)/announcements')).toBe(true); expect(feed.markRead).not.toHaveBeenCalled();
    const full = await render('announcements'); const rendered = text(full);
    cards.forEach(card => expect(rendered).toContain(card.title)); expect(feed.markRead).not.toHaveBeenCalled();
  });
  it.each([['gym', 'gym'], ['dance', 'academy'], ['yoga', 'studio'], ['martial_arts', 'academy'], ['studio', 'studio']] as const)('%s retains saved business nouns on Home and hub', async (type, place) => {
    state.type = type;
    expect(text(await render('home'))).toMatch(new RegExp(`From your ${place}`, 'i'));
    expect(text(await render('gym'))).toMatch(new RegExp(`Your ${place}`, 'i'));
  });
  it('membership retains contextual renewal and Freeze access', async () => {
    const tree = await render('gym'); press(tree, /Renew|Plans.*prices/i); await render('gym'); expect(destination('/(member)/gym', 'plans') || state.plans.mock.calls.some(([enabled]) => enabled === true)).toBe(true);
    press(tree, /Freeze requests/i); expect(destination('/(member)/freeze-requests')).toBe(true);
  });
  it('business hub keeps My classes independent of primary discovery and preserves Training', async () => {
    const tree = await render('gym'); press(tree, /My classes/i); expect(destination('/(member)/classes', 'bookings')).toBe(true);
    press(tree, /Trainers.*programmes|Instructors.*programmes|Teachers.*programmes/i); expect(destination('/(member)/classes', 'training')).toBe(true);
  });
  it('bookings section mounts the independent bookings-only Classes pane', async () => {
    state.section = 'bookings'; const tree = await render('classes'); const pane = nodes(tree).find(node => node.type === 'classes-pane');
    expect(pane?.props.bookingsOnly).toBe(true); expect(nodes(tree).some(node => node.type === 'training-section')).toBe(false);
  });
  it('trainer More opens native Training within the existing role boundary', async () => {
    state.trainer = true; const tree = await render('more'); press(tree, /Training/i);
    expect(destination('/(desk)/training')).toBe(true); expect(state.browser).not.toHaveBeenCalled();
  });
  it('front desk retains the authenticated web Training handoff', async () => {
    const tree = await render('more'); press(tree, /Training/i);
    expect(state.browser).toHaveBeenCalledWith('https://app.example/training'); expect(destination('/(desk)/training')).toBe(false);
  });
});
describe('NAVC Display palette compatibility', () => {
  it.each([true, false])('accent=%s uses the existing optional Display color contract', async accent => {
    const { Display } = await import('../../components/ui'); const tree = expand(createElement(Display, { accent, children: '42' } as Parameters<typeof Display>[0]));
    const figure = nodes(tree).find(node => node.type === 'text' && text(node) === '42'); expect(figure).toBeDefined();
    const styles = [figure?.props.style].flat(Infinity).filter(value => value && typeof value === 'object') as Array<Record<string, unknown>>;
    const color = Object.assign({}, ...styles).color;
    const baseline = expand(createElement(Display, { children: 'Baseline' }));
    const baselineText = nodes(baseline).find(node => node.type === 'text' && text(node) === 'Baseline');
    const baselineStyles = [baselineText?.props.style].flat(Infinity).filter(value => value && typeof value === 'object') as Array<Record<string, unknown>>;
    expect(color).toBe(accent ? UI_TOKENS.colors.light.primaryAction : Object.assign({}, ...baselineStyles).color);
  });
});
describe('NAVC announcement preview contract retains existing read lifecycle', () => {
  async function section(props: Record<string, unknown>) {
    const { AnnouncementsSection } = await import('../../components/announcements'); state.cursor = 0;
    return expand(createElement(AnnouncementsSection, { feed, timezone: 'Asia/Kolkata', ...props } as Parameters<typeof AnnouncementsSection>[0]));
  }
  it('compact preview renders two cards and View all delegates without reading the third', async () => {
    const onViewAll = vi.fn(); const tree = await section({ previewLimit: 2, onViewAll });
    expect(text(tree)).toContain(cards[0]!.title); expect(text(tree)).toContain(cards[1]!.title); expect(text(tree)).not.toContain(cards[2]!.title);
    press(tree, /^View all$/i); expect(onViewAll).toHaveBeenCalledTimes(1); expect(feed.markRead).not.toHaveBeenCalled();
  });
  it('full list renders all cards without creating read receipts by presentation alone', async () => {
    const tree = await section({ showAll: true, previewLimit: 2 }); cards.forEach(card => expect(text(tree)).toContain(card.title)); expect(feed.markRead).not.toHaveBeenCalled();
  });
  it('opening a compact card acknowledges its exact id/version', async () => {
    const tree = await section({ previewLimit: 2, onViewAll: vi.fn() }); press(tree, /Shared first closure/);
    expect(feed.markRead).toHaveBeenCalledWith(cards[0]!.announcementId, cards[0]!.versionNo);
    expect(feed.markRead).not.toHaveBeenCalledWith(cards[2]!.announcementId, cards[2]!.versionNo);
  });
});
