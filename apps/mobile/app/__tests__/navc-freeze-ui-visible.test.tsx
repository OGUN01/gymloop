import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, isValidElement, type ReactElement, type ReactNode } from 'react';
import { UI_TOKENS } from '@gymloop/shared';

// Fixture fields come only from pre-existing exported MemberSnapshot and the
// inferred public useMemberSnapshot return signature (no component bodies read).
const { state } = vi.hoisted(() => ({ state: {
  type: 'dance' as 'dance' | 'gym' | 'yoga' | 'martial_arts' | 'studio', slots: [] as unknown[], cursor: 0,
  effects: [] as Array<() => unknown>, error: false, loading: false,
  empty: false, desk: false, count: 1, section: undefined as string | string[] | undefined, push: vi.fn(), browser: vi.fn(), plans: vi.fn(), create: vi.fn(), cancel: vi.fn(),
} }));
const stored = 'Stored gym member trainer message';
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
    messages: [{ id: 'note', body: stored, sentAt: '2026-10-01T06:00:00Z', status: 'sent' }], consents: [],
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
  identity: state.desk ? { kind: 'staff', tenantId: 't1', staffId: 's1', userId: 'u1', role: 'front_desk' } : { kind: 'member', tenantId: 't1', memberId: 'm1', userId: 'u1' },
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
// Frozen existing hook fixture: freeze-ui-public-declarations.md, read before
// UI implementation. The command and hook are doubled; actual UI stays real.
const freezeState = {
  phase: 'ready' as const, offline: false, loadedAt: '2026-10-06T04:30:00Z', membershipId: '81100000-0000-4000-8000-000000000701',
  membership: { planName: 'Monthly Unlimited', status: 'active', startsOn: '2026-09-01', endsOn: '2026-12-31', recordedAgreedPricePaise: '150000', currency: 'INR' },
  requests: [],
};
vi.mock('../../lib/member-freeze-requests', () => ({ useMemberFreezeRequests: () => ({ state: freezeState, reload: vi.fn(async () => undefined), create: state.create, cancel: state.cancel }) }));
async function render() {
  const Screen = (await import('../(member)/freeze-requests')).default; let tree: ReactNode;
  for (let pass = 0; pass < 6; pass++) {
    state.cursor = 0; tree = expand(createElement(Screen)); state.effects.splice(0).forEach(effect => effect());
    for (let tick = 0; tick < 8; tick++) await Promise.resolve();
  }
  return tree;
}
function field(tree: ReactNode, label: RegExp) {
  const found = nodes(tree).find(node => typeof node.props.onChangeText === 'function' && [node.props.accessibilityLabel, node.props.placeholder].some(value => typeof value === 'string' && label.test(value)));
  expect(found, `editable ${label} field`).toBeDefined(); return found!;
}
function press(tree: ReactNode, label: RegExp) {
  const found = nodes(tree).find(node => typeof node.props.onPress === 'function' && [text(node), String(node.props.accessibilityLabel ?? '')].some(value => label.test(value.trim())));
  expect(found, `reachable ${label} control`).toBeDefined(); return (found?.props.onPress as () => unknown)();
}
beforeEach(() => {
  state.type = 'gym'; state.slots = []; state.cursor = 0; state.effects = []; state.error = false; state.loading = false; state.empty = false; state.desk = false; state.section = undefined;
  state.push.mockClear(); state.create.mockReset().mockResolvedValue({ ok: false, code: 'invalid_request', offline: false }); state.cancel.mockReset();
});
describe('NAVC-012 native Freeze copy and keyboard improvements preserve command', () => {
  it('shows one approval request notice without raw internal routes', async () => {
    const rendered = text(await render()); expect(rendered.match(/This is a request\. Your gym must approve it\./g)).toHaveLength(1);
    expect(rendered).not.toMatch(/\/(?:member|api)\/|\/\(member\)\//); expect(rendered).toMatch(/renew|buy|purchase request/i);
  });
  it('membership summary formats real dates for reading while retaining sold facts', async () => {
    const rendered = text(await render()); expect(rendered).toContain('Monthly Unlimited'); expect(rendered).toContain('₹1,500');
    expect(rendered).not.toContain('2026-09-01'); expect(rendered).not.toContain('2026-12-31'); expect(rendered).toMatch(/1\s+(?:Sep|September)|(?:Sep|September)\s+1/i); expect(rendered).toMatch(/31\s+(?:Dec|December)|(?:Dec|December)\s+31/i);
  });
  it('form is inside native keyboard avoidance and remains scrollable with keyboard taps', async () => {
    const tree = await render(); const keyboard = nodes(tree).find(node => node.type === 'keyboard'); expect(keyboard).toBeDefined();
    expect(nodes(keyboard).filter(node => node.type === 'input').length).toBeGreaterThanOrEqual(3);
    expect(nodes(tree).some(node => (node.type === 'scroll' || node.type === 'animated-scroll') && ['handled', 'always'].includes(String(node.props.keyboardShouldPersistTaps)))).toBe(true);
  });
  it('friendly display and keyboard wrapper still submit exact entered ISO dates, reason and membership', async () => {
    let tree = await render(); const inputs = nodes(tree).filter(node => typeof node.props.onChangeText === 'function'); expect(inputs).toHaveLength(3);
    const start = field(tree, /start|first/i); const end = field(tree, /end|last/i); const reason = field(tree, /reason|why/i);
    (start.props.onChangeText as (value: string) => void)('2026-10-10'); (end.props.onChangeText as (value: string) => void)('2026-10-17'); (reason.props.onChangeText as (value: string) => void)('Family trip out of station');
    tree = await render(); await press(tree, /Send request|Request freeze|Submit request/i); await render();
    expect(state.create).toHaveBeenCalledWith({ membershipId: freezeState.membershipId, startsOn: '2026-10-10', endsOn: '2026-10-17', reason: 'Family trip out of station' }); expect(state.create).toHaveBeenCalledTimes(1); expect(state.cancel).not.toHaveBeenCalled();
  });
});
