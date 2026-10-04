import { beforeEach, describe, expect, it, vi } from 'vitest';

const fixture = vi.hoisted(() => ({
  platform: 'android', online: true, permission: 'granted',
  states: [] as unknown[], cursor: 0, effects: [] as Array<() => unknown>,
  channel: vi.fn(), request: vi.fn(), token: vi.fn(), post: vi.fn(), open: vi.fn(),
  module: {} as Record<string, unknown>,
}));

vi.mock('react', () => ({
  useState: (initial: unknown) => {
    const index = fixture.cursor++;
    if (!(index in fixture.states)) fixture.states[index] = typeof initial === 'function' ? initial() : initial;
    return [fixture.states[index], (value: unknown) => {
      fixture.states[index] = typeof value === 'function' ? value(fixture.states[index]) : value;
    }];
  },
  useEffect: (effect: () => unknown) => { fixture.effects.push(effect); },
  useRef: (value: unknown) => {
    const index = fixture.cursor++;
    if (!(index in fixture.states)) fixture.states[index] = { current: value };
    return fixture.states[index];
  },
  useCallback: (callback: unknown) => callback,
  useMemo: (calculate: () => unknown) => calculate(),
}));
vi.mock('react-native', () => ({ Platform: { get OS() { return fixture.platform; } }, Linking: { openSettings: fixture.open } }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: async () => ({ isConnected: fixture.online, isInternetReachable: fixture.online }) }));
vi.mock('expo-secure-store', () => ({ getItemAsync: async () => '57428966-e440-45a5-a934-815c32319d5b', setItemAsync: vi.fn() }));
vi.mock('expo-crypto', () => ({ randomUUID: () => '57428966-e440-45a5-a934-815c32319d5b' }));
vi.mock('expo-notifications', () => fixture.module);
vi.mock('../../apps/mobile/lib/mobile-context', () => ({ useMobile: () => ({
  api: { post: fixture.post }, session: { user: { id: 'member-account' } },
  claims: { role: 'member', tenant_id: 'gym', member_id: 'member', sub: 'member-account' },
  online: fixture.online,
}) }));

let useMemberPush: typeof import('../../apps/mobile/lib/use-member-push').useMemberPush;

const render = () => { fixture.cursor = 0; return useMemberPush(); };
const settle = async () => { await new Promise((resolve) => setTimeout(resolve, 20)); };
const mount = async () => {
  render();
  for (const effect of fixture.effects) effect();
  await settle();
  return render();
};

beforeEach(async () => {
  vi.resetModules();
  vi.clearAllMocks();
  fixture.platform = 'android'; fixture.online = true; fixture.permission = 'granted';
  fixture.states = []; fixture.effects = [];
  fixture.channel.mockResolvedValue({ id: 'fitcruxx-updates' });
    fixture.request.mockImplementation(async () => ({ status: fixture.permission, granted: fixture.permission === 'granted' }));
  fixture.token.mockResolvedValue({ type: 'android', data: 'native-fcm-token'.repeat(12) });
  fixture.post.mockImplementation(async (path: string) => ({ ok: true, data: path.endsWith('push-settings')
    ? { preferences: [], devices: [], pushConfigured: false }
    : { deviceId: '9629b8c5-8a67-445d-a18a-b12c5be3db7b', tokenRevision: 1, active: true } }));
  fixture.module = {
    AndroidImportance: { DEFAULT: 3 }, setNotificationChannelAsync: fixture.channel,
    requestPermissionsAsync: fixture.request,
    getPermissionsAsync: async () => ({ status: fixture.permission, granted: fixture.permission === 'granted' }),
    getDevicePushTokenAsync: fixture.token,
    addPushTokenListener: () => ({ remove: vi.fn() }),
    addNotificationReceivedListener: () => ({ remove: vi.fn() }),
    addNotificationResponseReceivedListener: () => ({ remove: vi.fn() }),
  };
  ({ useMemberPush } = await import('../../apps/mobile/lib/use-member-push'));
});

describe('NFC-003/004 independent enable-action channel contract', () => {
  it('does not create channels or prompt consent while rendering and reading settings', async () => {
    render();
    for (const effect of fixture.effects) effect();
    await settle();
    expect(fixture.channel).not.toHaveBeenCalled();
    expect(fixture.request).not.toHaveBeenCalled();
    expect(fixture.token).not.toHaveBeenCalled();
  });

  it('awaits successful default Android channel creation before permission, token and registration', async () => {
    let complete: (() => void) | undefined;
    fixture.channel.mockImplementation(() => new Promise<void>((resolve) => { complete = resolve; }));
    const hook = await mount();
    const action = hook.enableNotifications();
    await settle();
    expect(fixture.channel).toHaveBeenCalledWith('fitcruxx-updates', expect.objectContaining({ name: 'FitCruxx updates', importance: 3 }));
    expect(fixture.request).not.toHaveBeenCalled();
    expect(fixture.token).not.toHaveBeenCalled();
    expect(fixture.post.mock.calls.some(([path]) => path === '/api/member/push-device')).toBe(false);
    complete?.();
    await action;
    expect(fixture.request).toHaveBeenCalledOnce();
    expect(fixture.token).toHaveBeenCalledOnce();
    expect(fixture.post).toHaveBeenCalledWith('/api/member/push-device', {
      installationId: '57428966-e440-45a5-a934-815c32319d5b', pushToken: 'native-fcm-token'.repeat(12), platform: 'android',
    });
  });

  it.each(['rejected', 'missing'])('refuses registration with actionable feedback when channel API is %s', async (failure) => {
    if (failure === 'missing') {
      delete fixture.module.setNotificationChannelAsync;
      vi.resetModules();
      vi.doMock('expo-notifications', () => fixture.module);
      ({ useMemberPush } = await import('../../apps/mobile/lib/use-member-push'));
    }
    else fixture.channel.mockRejectedValue(new Error('channel unavailable'));
    await (await mount()).enableNotifications();
    await settle();
    expect(fixture.request).not.toHaveBeenCalled();
    expect(fixture.token).not.toHaveBeenCalled();
    expect(fixture.post.mock.calls.some(([path]) => path === '/api/member/push-device')).toBe(false);
    expect(render().actionError).toEqual(expect.any(String));
    expect(render().actionError).toMatch(/channel|setup|notification|update|retry|try/i);
    expect(render().registration).toBeNull();
  });

  it.each(['ios', 'web'])('keeps %s preview free of Android channel and native registration', async (platform) => {
    fixture.platform = platform;
    await (await mount()).enableNotifications();
    expect(fixture.channel).not.toHaveBeenCalled();
    expect(fixture.token).not.toHaveBeenCalled();
  });

  it('does not acquire or queue a registration while offline', async () => {
    fixture.online = false;
    await (await mount()).enableNotifications();
    expect(fixture.token).not.toHaveBeenCalled();
    expect(fixture.post.mock.calls.some(([path]) => path === '/api/member/push-device')).toBe(false);
  });

  it('denied permission never forces navigation into OS settings', async () => {
    fixture.permission = 'denied';
    await (await mount()).enableNotifications();
    expect(fixture.open).not.toHaveBeenCalled();
    expect(render().settings).toEqual(expect.objectContaining({ preferences: expect.any(Array), devices: expect.any(Array) }));
  });
});
