import { beforeEach, describe, expect, it, vi } from 'vitest';

const fixture = vi.hoisted(() => ({
  platform: 'android', online: true, permission: 'granted', missingChannel: false,
  identity: { kind: 'member', userId: '74a2c026-8af0-4c75-9ea2-8b2b408f0fcf', tenantId: '83c3387b-7548-45aa-bc5f-146ed8b3ff2c', memberId: 'dbd7f814-762e-4f48-aa03-b53ab88977e5' } as Record<string, string> | undefined,
  events: [] as string[], states: [] as unknown[], cursor: 0, effects: [] as (() => unknown)[],
  channel: vi.fn(), request: vi.fn(), token: vi.fn(), post: vi.fn(), openSettings: vi.fn(),
}));
vi.mock('react', () => ({
  useState: (initial: unknown) => {
    const index = fixture.cursor++;
    if (!(index in fixture.states)) fixture.states[index] = typeof initial === 'function' ? initial() : initial;
    return [fixture.states[index], (value: unknown) => { fixture.states[index] = typeof value === 'function' ? value(fixture.states[index]) : value; }];
  },
  useRef: (initial: unknown) => { const index = fixture.cursor++; if (!(index in fixture.states)) fixture.states[index] = { current: initial }; return fixture.states[index]; },
  useCallback: (callback: unknown) => callback,
  useMemo: (callback: () => unknown) => callback(),
  useEffect: (effect: () => unknown) => { fixture.effects.push(effect); },
}));
vi.mock('react-native', () => ({ Platform: { get OS() { return fixture.platform; } }, Linking: { openSettings: fixture.openSettings } }));
vi.mock('../mobile-context', () => ({ useMobile: () => ({ identity: fixture.identity, api: { post: fixture.post } }) }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: async () => ({ isConnected: fixture.online, isInternetReachable: fixture.online }) }));
vi.mock('expo-secure-store', () => ({ getItemAsync: async () => '6eae41ab-3717-4c7b-a9f2-579659504a81', setItemAsync: vi.fn() }));
vi.mock('expo-crypto', () => ({ randomUUID: () => '6eae41ab-3717-4c7b-a9f2-579659504a81' }));
vi.mock('expo-notifications', () => ({
  AndroidImportance: { DEFAULT: 'sdk-default-importance' },
  get setNotificationChannelAsync() { return fixture.missingChannel ? undefined : fixture.channel; },
  getPermissionsAsync: async () => ({ status: fixture.permission, granted: fixture.permission === 'granted' }),
  requestPermissionsAsync: fixture.request,
  getDevicePushTokenAsync: fixture.token,
  getExpoPushTokenAsync: () => { throw new Error('Expo Push Service is outside the native contract'); },
  addPushTokenListener: () => ({ remove: vi.fn() }),
  addNotificationReceivedListener: () => ({ remove: vi.fn() }),
  addNotificationResponseReceivedListener: () => ({ remove: vi.fn() }),
}));
import { useMemberPush } from '../use-member-push';

const render = () => { fixture.cursor = 0; return useMemberPush(); };
const mount = async () => {
  render();
  for (const effect of fixture.effects.splice(0)) effect();
  await new Promise<void>(resolve => setTimeout(resolve, 0));
  return render();
};

beforeEach(() => {
  vi.clearAllMocks();
  fixture.identity = { kind: 'member', userId: '74a2c026-8af0-4c75-9ea2-8b2b408f0fcf', tenantId: '83c3387b-7548-45aa-bc5f-146ed8b3ff2c', memberId: 'dbd7f814-762e-4f48-aa03-b53ab88977e5' };
  fixture.platform = 'android'; fixture.online = true; fixture.permission = 'granted'; fixture.missingChannel = false;
  fixture.events = []; fixture.states = []; fixture.effects = [];
  fixture.channel.mockImplementation(async () => { fixture.events.push('channel'); });
  fixture.request.mockImplementation(async () => { fixture.events.push('permission'); return { status: fixture.permission, granted: fixture.permission === 'granted' }; });
  fixture.token.mockImplementation(async () => { fixture.events.push('native-token'); return { type: 'android', data: 'independent-native-fcm-token' }; });
  fixture.post.mockImplementation(async (path: string) => {
    if (path === '/api/member/push-device') fixture.events.push('registration');
    return { ok: true, data: path === '/api/member/push-device' ? { deviceId: '3776270f-11fa-410a-aa1f-568e465b65f4', tokenRevision: 1, active: true } : { preferences: [], devices: [], pushConfigured: false } };
  });
});

describe('NFC-003/004 explicit Android channel setup', () => {
  it('NTF-003 refuses malformed absent identity before any native setup or registration', async () => {
    fixture.identity = undefined;
    await (await mount()).enableNotifications();
    expect(fixture.channel).not.toHaveBeenCalled();
    expect(fixture.request).not.toHaveBeenCalled();
    expect(fixture.token).not.toHaveBeenCalled();
    expect(fixture.post.mock.calls.some(([path]) => path === '/api/member/push-device')).toBe(false);
    expect(render().actionError).toMatch(/sign.?in|log.?in|account/i);
  });
  it('permissive Android reaches native token and caller API without provider configuration', async () => {
    await (await mount()).enableNotifications();
    expect(fixture.token).toHaveBeenCalledOnce();
    expect(fixture.post).toHaveBeenCalledWith('/api/member/push-device', { installationId: '6eae41ab-3717-4c7b-a9f2-579659504a81', pushToken: 'independent-native-fcm-token', platform: 'android' });
  });
  it('render, settings reads and listener attachment do not create a channel, request permission or acquire a token', async () => {
    await mount();
    expect(fixture.channel).not.toHaveBeenCalled(); expect(fixture.request).not.toHaveBeenCalled(); expect(fixture.token).not.toHaveBeenCalled();
  });

  it('awaits channel completion before permission, native token and caller registration', async () => {
    let finishChannel!: () => void;
    fixture.channel.mockImplementation(() => new Promise<void>(resolve => { fixture.events.push('channel'); finishChannel = resolve; }));
    const pending = (await mount()).enableNotifications();
    await vi.waitFor(() => expect(fixture.channel).toHaveBeenCalled());
    expect(fixture.channel).toHaveBeenCalledWith('fitcruxx-updates', expect.objectContaining({ name: 'FitCruxx updates', importance: 'sdk-default-importance' }));
    expect(fixture.request).not.toHaveBeenCalled(); expect(fixture.token).not.toHaveBeenCalled();
    expect(fixture.events).toEqual(['channel']);
    finishChannel(); await pending;
    expect(fixture.events).toEqual(['channel', 'permission', 'native-token', 'registration']);
    expect(fixture.post).toHaveBeenCalledWith('/api/member/push-device', { installationId: '6eae41ab-3717-4c7b-a9f2-579659504a81', pushToken: 'independent-native-fcm-token', platform: 'android' });
  });

  it.each(['rejected', 'missing'])('refuses registration for a %s channel API and gives an actionable error', async failure => {
    fixture.missingChannel = failure === 'missing';
    if (failure === 'rejected') fixture.channel.mockRejectedValue(new Error('native channel failed'));
    await (await mount()).enableNotifications();
    expect(fixture.request).not.toHaveBeenCalled(); expect(fixture.token).not.toHaveBeenCalled();
    expect(fixture.post.mock.calls.some(([path]) => path === '/api/member/push-device')).toBe(false);
    expect(render().settings).toMatchObject({ preferences: [], devices: [], pushConfigured: false });
    expect(render().actionError).toMatch(/channel|notification|push/i);
    expect(render().actionError).toMatch(/try|retry|update|rebuild|configure|available|couldn.t|unable/i);
    expect(fixture.openSettings).not.toHaveBeenCalled();
  });

  it.each(['ios', 'web'])('does not create a channel or register a provider on %s', async platform => {
    fixture.platform = platform;
    await (await mount()).enableNotifications();
    expect(fixture.channel).not.toHaveBeenCalled(); expect(fixture.request).not.toHaveBeenCalled(); expect(fixture.token).not.toHaveBeenCalled();
    expect(fixture.post.mock.calls.some(([path]) => path === '/api/member/push-device')).toBe(false);
  });

  it('offline action never registers or acquires a token', async () => {
    fixture.online = false;
    await (await mount()).enableNotifications();
    expect(render().actionError).toMatch(/offline|connect|network|try/i);
    expect(fixture.token).not.toHaveBeenCalled();
    expect(fixture.post.mock.calls.some(([path]) => path === '/api/member/push-device')).toBe(false);
  });

  it('denied permission never forces OS settings or navigation', async () => {
    fixture.permission = 'denied';
    await (await mount()).enableNotifications();
    expect(fixture.openSettings).not.toHaveBeenCalled();
  });
});






