import { useCallback, useEffect, useRef, useState } from 'react';
import { getNetworkStateAsync } from 'expo-network';
import { Linking } from 'react-native';
import { useMobile } from './mobile-context';

/**
 * Member push registration and category preferences for the native app
 * (NTF-003/004/016 + pre-configuration amendment). The OS permission prompt
 * happens only inside `enableNotifications()` — a member action — never at
 * render. The FCM token comes from `getDevicePushTokenAsync()` (the native
 * Firebase token, never an Expo token) and is registered through the member
 * push API with the installation id this app first generated. Offline, the
 * action reports a clear error and never queues a registration that would
 * claim success; the in-app inbox remains the source of truth either way.
 *
 * The notifications module loads lazily on first use: the You screen renders
 * long before any Android push module must initialize, and where the native
 * module is unavailable (web preview, unsupported shell) the hook degrades to
 * the honest unconfigured state instead of crashing the screen.
 */

const INSTALLATION_KEY = 'push-installation-id';
const SETTINGS_PATH = '/api/member/push-settings';
const PREFERENCE_PATH = '/api/member/push-preference';

/** The seven DB categories, in their vocabulary order, with the missing-row default. */
export const PUSH_CATEGORY_DEFAULTS: Array<{ category: string; enabled: boolean }> = [
  { category: 'renewal', enabled: true },
  { category: 'payment', enabled: true },
  { category: 'fulfilment', enabled: true },
  { category: 'promotion', enabled: true },
  { category: 'motivation', enabled: true },
  { category: 'class_update', enabled: true },
  { category: 'announcement', enabled: true },
];

export type MemberPushSettings = {
  preferences: Array<{ category: string; enabled: boolean }>;
  devices: Array<{ id: string; lastSeenAt: string; active: boolean }>;
  pushConfigured: boolean;
};

type NotificationsModule = {
  getPermissionsAsync(): Promise<{ status: string; granted: boolean }>;
  requestPermissionsAsync(): Promise<{ status: string; granted: boolean }>;
  getDevicePushTokenAsync(): Promise<{ type: string; data: string }>;
};

/** The expo-notifications module, or null where the native layer is unavailable. */
async function notificationsModule(): Promise<NotificationsModule | null> {
  try {
    return await import('expo-notifications') as unknown as NotificationsModule;
  } catch {
    return null;
  }
}

type ApiReply<T> = { ok: true; data: T } | { ok: false; error: { code: string; message: string } };
type MobileApi = { post: (path: string, body: unknown) => Promise<ApiReply<unknown>> };

/** One stable installation id per app install: a fresh UUID, stored locally. */
async function freshId(): Promise<string> {
  if (typeof globalThis.crypto?.randomUUID === 'function') return globalThis.crypto.randomUUID();
  try {
    const crypto = await import('expo-crypto');
    return crypto.randomUUID();
  } catch {
    throw new Error('no-id-source');
  }
}
async function ensureInstallationId(): Promise<string> {
  try {
    const { getItemAsync, setItemAsync } = await import('expo-secure-store');
    const stored = await getItemAsync(INSTALLATION_KEY);
    if (stored !== null && /^[0-9a-f-]+$/.test(stored) && stored.includes('-')) return stored;
    const fresh = await freshId();
    void setItemAsync(INSTALLATION_KEY, fresh).catch(() => undefined);
    return fresh;
  } catch {
    const fresh = await freshId();
    return fresh;
  }
}

export function useMemberPush() {
  const apiRef = useRef<MobileApi | null>(null);
  const moduleRef = useRef<NotificationsModule | null>(null);
  const [settings, setSettings] = useState<MemberPushSettings | null>(null);
  const [loadFailed, setLoadFailed] = useState(false);
  const [permission, setPermission] = useState<string>('undetermined');
  const [actionError, setActionError] = useState<string | null>(null);
  const [working, setWorking] = useState(false);
  apiRef.current = useMobile().api as unknown as MobileApi;

  const readSettings = useCallback(async (live: { current: boolean }) => {
    const api = apiRef.current;
    if (api === null) return;
    const reply = await api.post(SETTINGS_PATH, {});
    if (!live.current) return;
    if (reply.ok && reply.data !== null && typeof reply.data === 'object') {
      const value = reply.data as Partial<MemberPushSettings>;
      setSettings({
        preferences: Array.isArray(value.preferences) ? value.preferences : PUSH_CATEGORY_DEFAULTS,
        devices: Array.isArray(value.devices) ? value.devices : [],
        pushConfigured: value.pushConfigured === true,
      });
      setLoadFailed(false);
    } else {
      setLoadFailed(true);
    }
  }, []);

  useEffect(() => {
    const live = { current: true };
    void readSettings(live);
    void notificationsModule()
      .then((module) => { if (live.current) moduleRef.current = module; return module === null ? null : module.getPermissionsAsync(); })
      .then((state) => { if (state !== null && live.current) setPermission(state.status); })
      .catch(() => { /* an unknown permission state stays undetermined — the ask remains behind the member action */ });
    return () => { live.current = false; };
  }, [readSettings]);

  const enableNotifications = useCallback(async () => {
    if (working) return;
    setActionError(null);
    const notifications = moduleRef.current;
    if (notifications === null) {
      setActionError('Notifications are not available on this device. Updates remain in the app.');
      return;
    }
    // Start the OS permission ask immediately inside the member action (NTF-016):
    // it is the very first thing the control triggers, before any network work.
    void notifications.requestPermissionsAsync()
      .then((asked) => setPermission(asked.status))
      .catch(() => { /* an unknown ask result keeps the undetermined state */ });
    const offline = await (async () => {
      try {
        const state = await getNetworkStateAsync();
        return state.isConnected === false || state.isInternetReachable === false;
      } catch {
        return false;
      }
    })();
    if (offline) {
      setActionError("That didn't go through — you are offline. Connect and try again.");
      return;
    }
    setWorking(true);
    try {
      // The ask above ran inside this same member action; the FCM registration
      // does not depend on the display permission: the token identifies the
      // installation, the OS permission only gates display.
      const tokenResult = await notifications.getDevicePushTokenAsync();
      if (tokenResult.type !== 'fcm' || typeof tokenResult.data !== 'string' || tokenResult.data === '') {
        setActionError('A registration number was not available yet. Try again.');
        return;
      }
      const installationId = await ensureInstallationId();
      const reply = await apiRef.current?.post('/api/member/push-device', { installationId, pushToken: tokenResult.data, platform: 'android' });
      if (!reply || !reply.ok) {
        setActionError('The device could not be registered. Try again.');
        return;
      }
      await readSettings({ current: true });
    } catch {
      setActionError("Enabling didn't complete. Check your connection and try again.");
    } finally {
      setWorking(false);
    }
  }, [readSettings, working]);

  const setPreference = useCallback(async (category: string, enabled: boolean) => {
    const previous = settings;
    const reply = await apiRef.current?.post(PREFERENCE_PATH, { category, enabled });
    if (reply !== undefined && reply.ok) {
      setSettings((current) => current === null ? current : {
        ...current,
        preferences: current.preferences.map((row) => row.category === category ? { category, enabled } : row),
      });
    } else if (previous !== null) {
      setSettings(previous);
    }
  }, [settings]);

  const openOsSettings = useCallback(async () => {
    // A denied permission is resolved in the OS settings, only on request (NTF-016).
    Linking.openSettings?.();
  }, []);

  return {
    settings: settings ?? { preferences: PUSH_CATEGORY_DEFAULTS, devices: [], pushConfigured: false },
    loadFailed,
    permission,
    actionError,
    working,
    enableNotifications,
    setPreference,
    openOsSettings,
  } as const;
}
