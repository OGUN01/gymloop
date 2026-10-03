import { beforeEach, describe, expect, it, vi } from 'vitest';

// Implementation-blind NTF native You→Notifications surface (NTF-016, NTF-003,
// NTF-009, pre-configuration amendment). Test-only React/native boundary: the
// actual screen runs its hooks; all provider decisions stay in real modules.
// FROZEN CONTRACT: proposal.md NTF-016 (permission prompt follows a member
// action; denied → OS settings only on request; no extra navigation tab),
// serial declarations (register/unregister/read/set results).
type Node = { type: unknown; props: Record<string, unknown> };
const h = vi.hoisted(() => ({
  cursor: 0, slots: [] as unknown[], effects: [] as Array<() => unknown>, changed: false,
  online: true,
  identity: { kind: 'member', userId: 'user-a', tenantId: 'tenant-a', memberId: 'member-a', role: 'member' } as Record<string, string>,
  post: vi.fn(),
  permission: 'undetermined' as string,
  deviceToken: 'fcm-fixture-token' as string | null,
  registerCalls: [] as Array<Record<string, unknown>>,
  openSettings: vi.fn(),
  requestPermission: vi.fn(),
}));
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
vi.mock('../mobile-context', () => ({ useMobile: () => ({ identity: h.identity, api: { post: h.post }, ready: true, nouns: { place: 'gym', plural: 'gyms', member: 'member', trainer: 'trainer', class: 'class' }, palette: {}, businessType: 'gym', appearance: 'light', supabase: {}, session: h.identity.kind === 'member' ? {} : null, signOut: vi.fn() }) }));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: vi.fn(), replace: vi.fn() }), useLocalSearchParams: () => ({}), Link: 'Link', Redirect: 'Redirect' }));
vi.mock('expo-secure-store', () => ({ setItemAsync: vi.fn(), getItemAsync: async () => null, deleteItemAsync: vi.fn() }));
vi.mock('expo-network', () => ({ useNetworkState: () => ({ isConnected: h.online, isInternetReachable: h.online }), getNetworkStateAsync: async () => ({ isConnected: h.online, isInternetReachable: h.online }), addNetworkStateListener: () => ({ remove: vi.fn() }) }));
// The contract pins the native FCM token path (getDevicePushTokenAsync), no Expo
// token masquerading as FCM. The dependency is added during implementation;
// the mock here defines the API shape the screen must use.
vi.mock('expo-notifications', () => ({
  getPermissionsAsync: async () => ({ status: h.permission, granted: h.permission === 'granted' }),
  requestPermissionsAsync: async () => { h.requestPermission(); return { status: h.permission, granted: h.permission === 'granted' }; },
  getDevicePushTokenAsync: async () => ({ type: 'fcm', data: h.deviceToken }),
  setNotificationHandler: vi.fn(),
  AndroidImportance: { DEFAULT: 3, HIGH: 4 },
}));
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', Image: 'Image', ScrollView: 'ScrollView', Modal: 'Modal', ActivityIndicator: 'ActivityIndicator', TextInput: 'TextInput', StyleSheet: { create: (styles: unknown) => styles }, AppState: { addEventListener: () => ({ remove: vi.fn() }) }, useColorScheme: () => 'light', Linking: { openSettings: h.openSettings } }));
vi.mock('lucide-react-native', () => ({ Bell: 'Bell', BellOff: 'BellOff', ChevronRight: 'ChevronRight', Check: 'Check', RefreshCw: 'RefreshCw', X: 'X' }));
vi.mock('../../components/ui', () => {
  const widgets = ['Screen', 'Eyebrow', 'Title', 'Display', 'Body', 'Rule', 'Status', 'Row', 'LedgerSection', 'SheetHeader', 'ActionButton', 'RowAction', 'StateMessage', 'EmptyState', 'LoadingState', 'Field', 'ChoiceList'];
  return { ...Object.fromEntries(widgets.map(type => [type, (props: Record<string, unknown>) => ({ type, props })])), Sheet: (props: Record<string, unknown>) => props.visible ? { type: 'Sheet', props } : null };
});
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
function press(label: RegExp) { const node = action(label); (node.props.onPress as () => void)(); }
const youSettings = {
  preferences: [
    { category: 'renewal', enabled: true }, { category: 'payment', enabled: true }, { category: 'fulfilment', enabled: true },
    { category: 'promotion', enabled: false }, { category: 'motivation', enabled: true }, { category: 'class_update', enabled: true }, { category: 'announcement', enabled: true },
  ],
  devices: [{ id: '78100000-0000-4000-8000-000000000001', lastSeenAt: '2026-10-03T05:00:00Z', active: true }],
};
beforeEach(async () => {
  vi.resetModules(); h.cursor = 0; h.slots = []; h.effects = []; h.changed = false; h.online = true; h.permission = 'undetermined'; h.deviceToken = 'fcm-fixture-token'; h.registerCalls = [];
  h.post.mockReset().mockImplementation(async (path: string, body: unknown) => {
    if (path === '/api/member/push-device') { h.registerCalls.push(body as Record<string, unknown>); return { ok: true, data: { deviceId: '78100000-0000-4000-8000-000000000001', tokenRevision: 1, active: true } }; }
    if (path === '/api/member/push-preference') return { ok: true, data: body };
    return { ok: true, data: youSettings };
  });
  const mod = (await import('../../app/(member)/you')) as { default: () => unknown };
  screen = mod.default as () => unknown;
});

describe('NTF native notifications section (red until built)', () => {
  it('renders notifications settings with every DB category and the enabled-by-default rule', async () => {
    await render();
    const output = text();
    expect(output).toMatch(/Notifications/i);
    for (const category of ['renewal', 'payment', 'fulfilment', 'promotion', 'motivation', 'class_update', 'announcement']) expect(output).toContain(category);
    expect(output).toMatch(/default/i);
  });
  it('never requests OS permission before a member action', async () => {
    await render();
    expect(h.requestPermission).not.toHaveBeenCalled();
  });
  it('asks through an explicit member control, then registers the native FCM token', async () => {
    await render();
    press(/enable|turn on|allow/i);
    expect(h.requestPermission).toHaveBeenCalled();
    await new Promise(resolve => setTimeout(resolve, 0));
    await render();
    expect(h.registerCalls[0]).toMatchObject({ platform: 'android' });
    expect(JSON.stringify(h.registerCalls[0])).not.toContain('Expo');
  });
  it('shows the unconfigured-provider copy, never a fake delivered state', async () => {
    await render();
    expect(text()).toMatch(/Push isn't configured\. Updates remain in the app\./);
  });
  it('current device list shows only safe facts', async () => {
    await render();
    const output = text();
    expect(output).toMatch(/Last seen|last seen/i);
    expect(output).not.toMatch(/fcm|token/i);
  });
  it('denied permission opens OS settings only on request', async () => {
    h.permission = 'denied';
    await render();
    press(/open settings/i);
    expect(h.openSettings).toHaveBeenCalled();
  });
  it('offline shows a clear error and never queues a registration claiming success', async () => {
    h.online = false;
    await render();
    press(/enable|turn on|allow/i);
    await new Promise(resolve => setTimeout(resolve, 0));
    await render();
    expect(h.registerCalls).toEqual([]);
    expect(text()).toMatch(/that didn't go through|no connection|offline|try again/i);
  });
});
