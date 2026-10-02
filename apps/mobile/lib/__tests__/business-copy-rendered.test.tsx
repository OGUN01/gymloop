import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, isValidElement, type ReactElement, type ReactNode } from 'react';
import { UI_TOKENS } from '@gymloop/shared';
import type { MemberSnapshot } from '../mobile-data';

// Fixture fields come only from pre-existing exported MemberSnapshot and the
// inferred public useMemberSnapshot return signature (no component bodies read).
const { state } = vi.hoisted(() => ({ state: {
  type: 'dance' as 'dance' | 'gym', slots: [] as unknown[], cursor: 0,
  effects: [] as Array<() => unknown>, error: false, loading: false,
  empty: false, desk: false, count: 1,
} }));
const stored = 'Stored gym member trainer message';
const nouns = {
  dance: { place: 'academy', session: 'class', sessions: 'classes', class: 'batch', classes: 'batches', member: 'student', members: 'students', trainer: 'instructor' },
  gym: { place: 'gym', session: 'session', sessions: 'sessions', class: 'class', classes: 'classes', member: 'member', members: 'members', trainer: 'trainer' },
};
function snapshot(): MemberSnapshot {
  return {
    member: { fullName: 'Aarav Sharma', memberCode: 'BIZ-101', email: 'aarav@example.test', phone: '+917000000101', goal: 3, restDays: [] },
    gym: { name: 'BIZ Academy', displayName: 'BIZ Academy', code: 'BIZ70A', timezone: 'Asia/Kolkata', city: 'Mumbai', state: null, branchName: 'Main', branchAddress: null },
    membership: { status: 'active', startsOn: '2026-10-01', endsOn: '2026-10-31', planName: 'Monthly' },
    visits: state.empty ? [] : [{ id: 'v1', checkedInAt: '2026-10-01T06:00:00Z', source: 'qr' }],
    weekVisits: 1, weekStart: '2026-09-28', streak: { current: 1, unit: 'week', missed: [] }, receipts: [],
    messages: [{ id: 'note', body: stored, sentAt: '2026-10-01T06:00:00Z', status: 'sent' }], consents: [],
    addOns: [{ id: 'pack', name: 'Movement pack', status: 'active', totalPaise: '150000', currency: 'INR', sessionsUsed: 1, sessionsTotal: 3 }],
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
vi.mock('expo-router', () => ({ useRouter: () => ({ push: vi.fn(), replace: vi.fn() }), useLocalSearchParams: () => ({}), Tabs: Object.assign(host('tabs'), { Screen: host('tab') }), Link: host('link') }));
vi.mock('expo-camera', () => ({ CameraView: host('camera'), useCameraPermissions: () => [{ granted: false }, vi.fn()] }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: async () => ({ isConnected: false }), addNetworkStateListener: () => ({ remove: () => undefined }) }));
vi.mock('expo-crypto', () => ({ randomUUID: () => 'event' }));
vi.mock('expo-haptics', () => ({ selectionAsync: async () => undefined, impactAsync: async () => undefined, notificationAsync: async () => undefined }));
vi.mock('expo-web-browser', () => ({ openBrowserAsync: async () => undefined }));
vi.mock('expo-secure-store', () => ({ getItemAsync: async () => null, setItemAsync: async () => undefined, deleteItemAsync: async () => undefined }));
vi.mock('expo-font', () => ({ useFonts: () => [true, null], isLoaded: () => true, loadAsync: async () => undefined }));
vi.mock('../../../../packages/shared/assets/fonts/GoogleSans-Medium.ttf', () => ({ default: 'test-font' }));
vi.mock('react-native-svg', () => ({ default: host('svg'), Svg: host('svg'), Path: host('path'), G: host('g'), Circle: host('circle'), Rect: host('rect'), Defs: host('defs'), ClipPath: host('clipPath'), LinearGradient: host('linearGradient'), RadialGradient: host('radialGradient'), Stop: host('stop') }));
vi.mock('react-native-safe-area-context', () => ({ SafeAreaView: host('safe-area'), useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }) }));
vi.mock('lucide-react-native', () => new Proxy({}, { get: (_target, name) => name === 'then' ? undefined : host(String(name)), has: () => true }));
vi.mock('../mobile-context', () => ({ useMobile: () => ({
  identity: state.desk ? { kind: 'staff', tenantId: 't1', staffId: 's1', userId: 'u1', role: 'front_desk' } : { kind: 'member', tenantId: 't1', memberId: 'm1', userId: 'u1' },
  session: { user: { email: 'aarav@example.test' } }, supabase: {}, api: { post: vi.fn() }, palette: UI_TOKENS.colors.light,
  businessType: state.type, nouns: nouns[state.type], appearance: 'system', setAppearance: vi.fn(), signOut: vi.fn(), webOrigin: 'https://app.example',
}) }));
vi.mock('../use-member-snapshot', () => ({ useMemberSnapshot: () => ({ data: state.error ? null : snapshot(), error: null, loading: state.loading, reload: vi.fn() }) }));
vi.mock('../mobile-data', async (original) => ({ ...await original<Record<string, unknown>>(),
  loadDeskMembers: async () => state.empty ? [] : Array.from({ length: state.count }, (_, index) => ({ id: `m${index}`, fullName: `Aarav Sharma ${index}`, phone: '+917000000101', status: 'active', memberCode: `BIZ-10${index}` })),
  loadDeskFollowUps: async () => [], loadDefaultBranch: async () => 'branch1',
}));
vi.mock('../offline-check-in', () => ({ loadOfflineCheckIns: async () => [], drainOfflineCheckIns: async () => [], saveOfflineCheckIn: vi.fn(), shouldReplayOnSignal: () => false, createReplayCoordinator: () => ({ requestReplay: vi.fn() }) }));

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
function accessible(tree: ReactNode): string {
  return nodes(tree).map((node) => [node.props.accessibilityLabel, node.props.accessibilityHint, node.props.title, node.props.alt, node.props.placeholder].filter((value) => typeof value === 'string').join(' ')).join(' ');
}
const routes = {
  home: () => import('../../app/(member)/index'), activity: () => import('../../app/(member)/activity'),
  gym: () => import('../../app/(member)/gym'), you: () => import('../../app/(member)/you'),
  desk: () => import('../../app/(desk)/index'), members: () => import('../../app/(desk)/members'), followUps: () => import('../../app/(desk)/follow-ups'),
};
async function render(name: keyof typeof routes) {
  state.desk = ['desk', 'members', 'followUps'].includes(name);
  const Screen = (await routes[name]()).default;
  let tree: ReactNode;
  for (let pass = 0; pass < 6; pass += 1) {
    state.cursor = 0; tree = expand(createElement(Screen));
    for (const effect of state.effects.splice(0)) await effect();
    for (let tick = 0; tick < 8; tick += 1) await Promise.resolve();
  }
  return tree;
}
const noDefaultWords = (tree: ReactNode) => {
  expect(`${text(tree)} ${accessible(tree)}`.replaceAll(stored, '')).not.toMatch(/\b(?:gym|member|members|trainer)\b/i);
};
beforeEach(() => { state.type = 'dance'; state.slots = []; state.cursor = 0; state.effects = []; state.error = false; state.loading = false; state.empty = false; state.desk = false; state.count = 1; });

describe('BIZ-012/021 rendered native vocabulary and accessible names', () => {
  it.each(Object.keys(routes) as Array<keyof typeof routes>)('dance %s renders without default words', async (name) => {
    noDefaultWords(await render(name));
  });
  it.each(['home', 'activity', 'gym'] as const)('dance %s empty/error text varies too', async (name) => {
    state.error = name !== 'activity'; state.empty = true; noDefaultWords(await render(name));
  });
  it('dance Home exposes an academy scanner hint and keeps stored messages literal', async () => {
    const tree = await render('home'); expect(accessible(tree)).toContain('Opens the camera to scan your academy QR code');
    expect(text(tree)).toContain('Latest from your academy'); expect(text(tree)).toContain(stored);
  });
  it('dance Gym renders classes used and the student scanner hint', async () => {
    const tree = await render('gym'); expect(text(tree)).toContain('Academy code');
    expect(nodes(tree).some((node) => text(node) === 'Academy'), 'primitive-4 screen title uses the capitalized place').toBe(true);
    const usage = nodes(tree).map(text).filter((value) => /\bused\b/i.test(value)).sort((left, right) => left.length - right.length)[0];
    expect(usage).toBeDefined();
    expect(usage).toMatch(/\b1\b/); expect(usage).toMatch(/\b3\b/); expect(usage).toMatch(/\bclasses\b/);
    expect(accessible(tree)).toContain('Opens the student check-in scanner');
  });
  it('dance You labels the profile and account with the correct noun', async () => {
    const tree = await render('you'); expect(text(tree)).toContain('Verified student');
    expect(accessible(tree)).toMatch(/academy code BIZ70A/i);
  });
  it('gym preserves the specified Home, Gym and You legacy wording', async () => {
    state.type = 'gym'; const home = await render('home'); expect(text(home)).toContain('Latest from your gym'); expect(accessible(home)).toContain('Opens the camera to scan your gym QR code');
    state.slots = []; const gym = await render('gym'); expect(text(gym)).toContain('Gym code'); expect(accessible(gym)).toContain('Opens the member check-in scanner');
    state.slots = []; const you = await render('you'); expect(text(you)).toContain('Verified member'); expect(accessible(you)).toMatch(/gym code BIZ70A/i);
  });
  it.each(['desk', 'members'] as const)('dance %s counts use student for one and students for more', async (name) => {
    const one = await render(name); expect(text(one)).toMatch(/\b1 student\b/); expect(text(one)).not.toMatch(/\b1 students\b/);
    state.slots = []; state.count = 2; const two = await render(name); expect(text(two)).toMatch(/\b2 students\b/);
  });
  it.each(['desk', 'members', 'followUps'] as const)('dance %s empty state also has no default nouns', async (name) => {
    state.empty = true; noDefaultWords(await render(name));
  });
  it('the real loading primitive changes both visible text and its accessible name', async () => {
    const { LoadingState } = await import('../../components/ui'); const tree = expand(createElement(LoadingState));
    noDefaultWords(tree); expect(text(tree)).toContain('Loading your academy'); expect(accessible(tree)).toContain('Loading your academy');
  });
  it.each([false, true])('role tabs use tenant vocabulary (desk=%s) and a neutral place glyph', async (desk) => {
    const { RoleTabs } = await import('../../components/role-tabs'); const tree = expand(createElement(RoleTabs, { desk }));
    const titles = nodes(tree).filter((node) => node.type === 'tab').map((node) => (node.props.options as { title?: string } | undefined)?.title).join(' ');
    expect(titles).toContain(desk ? 'Students' : 'My academy'); expect(titles).not.toMatch(/\b(?:gym|members)\b/i);
    if (!desk) {
      const place = nodes(tree).find((node) => (node.props.options as { title?: string } | undefined)?.title === 'My academy');
      const icon = (place?.props.options as { tabBarIcon?: (props: object) => ReactNode } | undefined)?.tabBarIcon?.({ color: '#000000', size: 24 });
      expect(nodes(expand(icon)).map((node) => String(node.type)).join(' ')).toMatch(/Building/i);
    }
  });
});
