import { useCallback, useEffect, useRef, useState } from 'react';
import { getNetworkStateAsync } from 'expo-network';
import { Linking, Platform } from 'react-native';
import { PUSH_ANDROID_CHANNEL_ID, PUSH_ANDROID_CHANNEL_NAME } from '@gymloop/shared';
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

export type NotificationsModule = {
  AndroidImportance?: { DEFAULT: number };
  setNotificationChannelAsync?(channelId: string, channel: { name: string; importance: number }): Promise<unknown>;
  getPermissionsAsync(): Promise<{ status: string; granted: boolean }>;
  requestPermissionsAsync(): Promise<{ status: string; granted: boolean }>;
  getDevicePushTokenAsync(): Promise<{ type: string; data: string }>;
  getLastNotificationResponseAsync?(): Promise<unknown>;
  addNotificationReceivedListener?(listener: (notification: unknown) => void): { remove: () => void };
  addNotificationResponseReceivedListener?(listener: (response: unknown) => void): { remove: () => void };
};

/** The expo-notifications module, or null where the native layer is unavailable. */
export async function notificationsModule(): Promise<NotificationsModule | null> {
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
  const busyRef = useRef(false);
  const liveRef = useRef(true);
  const callerRef = useRef<string | null>(null);
  const memberRef = useRef(false);
  const registeredCallerRef = useRef<string | null>(null);
  const [settings, setSettings] = useState<MemberPushSettings | null>(null);
  const [loadFailed, setLoadFailed] = useState(false);
  const [permission, setPermission] = useState<string>('undetermined');
  const [actionError, setActionError] = useState<string | null>(null);
  const [working, setWorking] = useState(false);
  const [registration, setRegistration] = useState<{ deviceId: string; tokenRevision: number } | null>(null);
  const mobile = useMobile();
  apiRef.current = mobile.api as unknown as MobileApi;
  const caller = mobile.identity?.kind === 'member'
    ? `${mobile.identity.userId}:${mobile.identity.tenantId}:${mobile.identity.memberId}`
    : null;
  callerRef.current = caller;
  memberRef.current = mobile.identity?.kind === 'member';

  const readSettings = useCallback(async (live: { current: boolean }) => {
    const api = apiRef.current;
    const readCaller = callerRef.current;
    if (api === null) return;
    const reply = await api.post(SETTINGS_PATH, {});
    if (!live.current || !liveRef.current || callerRef.current !== readCaller || apiRef.current !== api) return;
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
    liveRef.current = true;
    return () => { liveRef.current = false; };
  }, []);

  useEffect(() => {
    setRegistration(null);
  }, [caller]);

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
    if (busyRef.current) return;
    setActionError(null);
    if (Platform.OS !== 'android') {
      setActionError('Push notifications are available on Android. Updates remain in the app.');
      return;
    }
    if (!memberRef.current) {
      setActionError('Sign in as a member to enable notifications. Updates remain in the app.');
      return;
    }
    const notifications = moduleRef.current;
    if (notifications === null) {
      setActionError('Notifications are not available on this device. Updates remain in the app.');
      return;
    }
    const actionCaller = callerRef.current;
    const actionApi = apiRef.current;
    const isCurrent = () => liveRef.current && memberRef.current && callerRef.current === actionCaller && apiRef.current === actionApi;
    busyRef.current = true;
    setWorking(true);
    try {
      if (typeof notifications.setNotificationChannelAsync !== 'function' || notifications.AndroidImportance?.DEFAULT === undefined) {
        setActionError('The notification channel is unavailable. Update the app and try again. Updates remain in the app.');
        return;
      }
      try {
        const channel = await notifications.setNotificationChannelAsync(PUSH_ANDROID_CHANNEL_ID, {
          name: PUSH_ANDROID_CHANNEL_NAME, importance: notifications.AndroidImportance.DEFAULT,
        });
        if (channel === null) throw new Error('notification-channel-unavailable');
      } catch {
        if (isCurrent()) setActionError('The notification channel could not be set up. Try again. Updates remain in the app.');
        return;
      }
      if (!isCurrent()) return;
      const asked = await notifications.requestPermissionsAsync();
      if (!isCurrent()) return;
      setPermission(asked.status);
      if (!asked.granted) {
        setActionError('Notifications are not allowed. You can enable them in device settings. Updates remain in the app.');
        return;
      }
      const offline = await (async () => {
        try {
          const state = await getNetworkStateAsync();
          return state.isConnected === false || state.isInternetReachable === false;
        } catch {
          return false;
        }
      })();
      if (!isCurrent()) return;
      if (offline) {
        setActionError("That didn't go through — you are offline. Connect and try again.");
        return;
      }
      const tokenResult = await notifications.getDevicePushTokenAsync();
      if (!isCurrent()) return;
      if (tokenResult.type !== 'android' || typeof tokenResult.data !== 'string' || tokenResult.data === '') {
        setActionError('A registration number was not available yet. Try again.');
        return;
      }
      const installationId = await ensureInstallationId();
      if (!isCurrent()) return;
      const reply = await actionApi?.post('/api/member/push-device', { installationId, pushToken: tokenResult.data, platform: 'android' });
      if (!isCurrent()) return;
      if (!reply || !reply.ok) {
        setActionError('The device could not be registered. Try again.');
        return;
      }
      // Keep the registered device identity: push receipt/open evidence
      // (NTF-009) is only meaningful against this accepted device revision.
      const registered = reply.data as { deviceId?: string; tokenRevision?: number };
      if (typeof registered?.deviceId === 'string' && typeof registered?.tokenRevision === 'number') {
        registeredCallerRef.current = actionCaller;
        setRegistration({ deviceId: registered.deviceId, tokenRevision: registered.tokenRevision });
      }
      await readSettings({ current: true });
    } catch {
      if (isCurrent()) setActionError("Enabling didn't complete. Check your connection and try again.");
    } finally {
      busyRef.current = false;
      if (liveRef.current) setWorking(false);
    }
  }, [readSettings]);

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
    registration: registeredCallerRef.current === caller ? registration : null,
    enableNotifications,
    setPreference,
    openOsSettings,
  } as const;
}
