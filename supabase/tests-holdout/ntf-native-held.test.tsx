// Independent NTF native adversarial boundary: rendered through the real You
// screen and the mocked expo-notifications API shape the contract pins (native
// FCM token, response listeners). All suite judgments are behavior-level; no
// invented helper modules. Red until the notifications section exists.
import { beforeEach, expect, it, vi } from 'vitest';

type Node = { type: unknown; props: Record<string, unknown> };
const h = vi.hoisted(() => ({
  cursor: 0, slots: [] as unknown[], effects: [] as Array<() => unknown>, changed: false,
  online: true, permission: 'granted' as string, deviceToken: 'fcm-holdout-secret-token' as string | null,
  post: vi.fn(), routerPush: vi.fn(), openSettings: vi.fn(), requestPermission: vi.fn(),
  responseListener: null as ((event: unknown) => unknown) | null, registerListener: null as ((event: unknown) => unknown) | null,
  registerCalls: [] as Array<Record<string, unknown>>,
  supabase: { rpc: async () => ({ data: null, error: { code: 'P0002', message: 'WhatsApp settings unavailable' } }) },
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
    useMemo: memo, useCallback: (callback: unknown, deps?: unknown[]) => memo(() => callback, deps),
    useEffect: (effect: () => unknown, deps?: unknown[]) => memo(() => { h.effects.push(effect); return undefined; }, deps),
  };
  return { ...actual, ...hooks, default: { ...(actual.default as Record<string, unknown>), ...hooks } };
}
vi.mock('react', async original => mockReactHooks(await original<Record<string, unknown>>()));
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => ({ identity: { kind: 'member', userId: 'user-a', tenantId: 'tenant-a', memberId: 'member-a', role: 'member' }, api: { post: h.post }, ready: true, nouns: { place: 'gym', plural: 'gyms', member: 'member', trainer: 'trainer', class: 'class' }, palette: {}, businessType: 'gym', appearance: 'light', supabase: h.supabase, session: {}, signOut: vi.fn() }) }));
vi.mock('expo-router', () => ({ useRouter: () => ({ push: h.routerPush, replace: vi.fn() }), useLocalSearchParams: () => ({}), Link: 'Link', Redirect: 'Redirect', usePathname: () => '/(member)/you' }));
vi.mock('expo-secure-store', () => ({ setItemAsync: vi.fn(), getItemAsync: async () => null, deleteItemAsync: vi.fn() }));
vi.mock('expo-network', () => ({ useNetworkState: () => ({ isConnected: h.online, isInternetReachable: h.online }), getNetworkStateAsync: async () => ({ isConnected: h.online, isInternetReachable: h.online }), addNetworkStateListener: () => ({ remove: vi.fn() }) }));
vi.mock('expo-notifications', () => ({
  getPermissionsAsync: async () => ({ status: h.permission, granted: h.permission === 'granted' }),
  requestPermissionsAsync: async () => { h.requestPermission(); return { status: h.permission, granted: h.permission === 'granted' }; },
  getDevicePushTokenAsync: async () => ({ type: 'fcm', data: h.deviceToken }),
  getLastNotificationResponseAsync: async () => null,
  setNotificationHandler: vi.fn(),
  addNotificationResponseReceivedListener: (listener: (event: unknown) => unknown) => { h.responseListener = listener; return { remove: vi.fn() }; },
  addNotificationReceivedListener: (listener: (event: unknown) => unknown) => { h.registerListener = listener; return { remove: vi.fn() }; },
  setNotificationChannelAsync: vi.fn(),
  AndroidImportance: { DEFAULT: 3, HIGH: 4 },
}));
vi.mock('react-native', () => ({ View: 'View', Text: 'Text', Pressable: 'Pressable', Image: 'Image', ScrollView: 'ScrollView', Modal: 'Modal', ActivityIndicator: 'ActivityIndicator', TextInput: 'TextInput', StyleSheet: { create: (styles: unknown) => styles }, AppState: { addEventListener: () => ({ remove: vi.fn() }) }, useColorScheme: () => 'light', Linking: { openSettings: h.openSettings } }));
vi.mock('lucide-react-native', () => ({ Bell: 'Bell', BellOff: 'BellOff', ChevronRight: 'ChevronRight', Check: 'Check', RefreshCw: 'RefreshCw', X: 'X' }));
vi.mock('../../apps/mobile/components/ui', () => {
  const widgets = ['Screen', 'Eyebrow', 'Title', 'Display', 'Body', 'Rule', 'Status', 'Row', 'LedgerSection', 'SheetHeader', 'ActionButton', 'RowAction', 'StateMessage', 'EmptyState', 'LoadingState', 'ErrorRetry', 'Field', 'ChoiceList'];
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
  // A quiet render is not completion of lazy native-module/listener setup.
  // NTF-009/016 require the real mounted callback path, within a bounded wait.
  await vi.waitFor(async () => {
    h.cursor = 0; h.changed = false; nodes = []; flatten(screen());
    const effects = h.effects.splice(0); effects.forEach(effect => effect());
    await new Promise(resolve => setTimeout(resolve, 0));
    expect(h.changed, 'Screen still updating').toBe(false);
    expect(h.effects, 'Screen still has pending effects').toHaveLength(0);
    expect(h.responseListener, 'Mounted notification response listener').not.toBeNull();
  });
}
function text() { return JSON.stringify(nodes.map(node => node.props)); }
function action(label: RegExp) {
  const node = nodes.find(node => typeof node.props.onPress === 'function' && label.test(String(node.props.children ?? node.props.title ?? node.props.accessibilityLabel ?? '')));
  expect(node, `Missing actual screen control ${label}`).toBeDefined(); return node!;
}
beforeEach(async () => {
  vi.resetModules(); h.cursor = 0; h.slots = []; h.effects = []; h.changed = false; h.online = true; h.permission = 'granted';
  h.deviceToken = 'fcm-holdout-secret-token'; h.post.mockReset(); h.routerPush.mockReset(); h.openSettings.mockReset();
  h.requestPermission.mockReset(); h.responseListener = null; h.registerListener = null; h.registerCalls = [];
  h.post.mockImplementation(async (path: string, body: unknown) => {
    if (path === '/api/member/push-device') { h.registerCalls.push(body as Record<string, unknown>); return { ok: true, data: { deviceId: '78900000-0000-4000-8000-000000000001', tokenRevision: 1, active: true } }; }
    return { ok: true, data: {} };
  });
  const mod = (await import('../../apps/mobile/app/(member)/you')) as { default: () => unknown };
  screen = mod.default as () => unknown;
});

it('mount registers a notification response listener (the open evidence path exists on screen)', async () => {
  await render();
  expect(h.responseListener).not.toBeNull();
});

it('an adversarial payload with an arbitrary URL/external intent never routes and never mutates', async () => {
  await render();
  for (const payload of [
    { notificationId: '78900000-0000-4000-8000-000000000001', url: 'https://evil.example/steal' },
    { notificationId: '78900000-0000-4000-8000-000000000001', url: 'intent://drop', action: 'PAY' },
    { notificationId: '78900000-0000-4000-8000-000000000002', tenantId: 'other-tenant' },
  ]) {
    h.routerPush.mockReset();
    h.responseListener?.({ notification: { request: { content: { data: payload } } }, actionIdentifier: 'expo.modules.notifications.actions.DEFAULT' });
    expect(h.routerPush.mock.calls).toEqual([]);
    expect(h.post.mock.calls.filter(call => String(call[0]).includes('push-event'))).toEqual([]);
  }
});

it('only authorized device registration carries the native token; screen and unrelated posts expose no provider artifact', async () => {
  await render();
  action(/enable|turn on|allow/i).props.onPress();
  await new Promise(resolve => setTimeout(resolve, 0));
  await render();
  expect(text()).not.toMatch(/fcm|token|installation/i);
  // NTF-003 explicitly submits the native token to the member device writer;
  // NTF-013 forbids exposing it through display or unrelated commands.
  expect(h.registerCalls).toHaveLength(1);
  expect(h.registerCalls[0]).toEqual({
    installationId: expect.stringMatching(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i),
    pushToken: h.deviceToken,
    platform: 'android',
  });
  expect(JSON.stringify(h.post.mock.calls.filter(call => call[0] !== '/api/member/push-device'))).not.toMatch(/fcm-holdout-secret-token|pushToken|providerMessageId|serviceAccount/i);
  expect(JSON.stringify(h.registerCalls)).not.toMatch(/Expo/i);
});

it('offline registration fails loudly and never queues a claimed success', async () => {
  h.online = false;
  await render();
  action(/enable|turn on|allow/i).props.onPress();
  await new Promise(resolve => setTimeout(resolve, 0));
  await render();
  expect(h.registerCalls).toEqual([]);
  expect(text()).toMatch(/that didn't go through|no connection|offline|try again/i);
});

it('denied permission never silently proceeds; OS settings open only on explicit member request', async () => {
  h.permission = 'denied';
  await render();
  expect(text()).toMatch(/denied|blocked|not allowed|settings/i);
  h.openSettings.mockReset();
  action(/open settings/i).props.onPress();
  expect(h.openSettings).toHaveBeenCalled();
  expect(h.requestPermission).not.toHaveBeenCalled();
});
