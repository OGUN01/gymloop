import { createApiClient, type ApiClient, type ApiFetch } from '@gymloop/api-client';
import { businessNouns, isBusinessType, mobileClientEnv, type BusinessType, type BusinessNouns, type GymloopIdentity, UI_TOKENS } from '@gymloop/shared';
import { Archivo_400Regular, Archivo_500Medium, Archivo_600SemiBold, Archivo_700Bold, useFonts } from '@expo-google-fonts/archivo';
import archivoDisplay from '../assets/fonts/ArchivoExtraCondensed-ExtraBold.ttf';
import archivoDisplayBold from '../assets/fonts/ArchivoExtraCondensed-Bold.ttf';
import type { Session, SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import * as SecureStore from 'expo-secure-store';
import * as SplashScreen from 'expo-splash-screen';
import { AppState, StatusBar, useColorScheme } from 'react-native';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { clearOfflineCheckIns } from './offline-check-in';
import { createMobileSupabase, resolveNativeMobileSession, signOutMobile } from './native-session';
import { clearShopCache } from './shop-cache';
import { clearAnnouncementCache } from './announcements';

import { BUSINESS_TYPE_STORAGE_KEY, encodePersistedBusinessType, readPersistedBusinessType, resolveBusinessType } from './business-type';

const APPEARANCE_KEY = 'gymloop.appearance';
export type AppearanceMode = 'system' | 'light' | 'dark';
type MobilePalette = (typeof UI_TOKENS.colors)[keyof typeof UI_TOKENS.colors];

type MobileContextValue = {
  api: ApiClient;
  appearance: AppearanceMode;
  identity: GymloopIdentity;
  businessType: BusinessType | null;
  nouns: BusinessNouns;
  palette: MobilePalette;
  ready: boolean;
  session: Session | null;
  supabase: SupabaseClient<Database>;
  setAppearance(mode: AppearanceMode): Promise<void>;
  signOut(): Promise<void>;
  /** Configured web/API origin — legal rows open public pages here. */
  webOrigin: string;
};

const MobileContext = createContext<MobileContextValue | null>(null);
void SplashScreen.preventAutoHideAsync().catch(() => undefined);
const config = mobileClientEnv();
const supabase = createMobileSupabase({
  supabaseUrl: config.EXPO_PUBLIC_SUPABASE_URL,
  supabaseAnonKey: config.EXPO_PUBLIC_SUPABASE_ANON_KEY,
});

function scopeKey(identity: GymloopIdentity): string | null {
  if (identity.kind === 'member') return `${identity.userId}:${identity.tenantId}:${identity.memberId}`;
  return null;
}

/** Attempt both revocations immediately, including when a cleanup throws before returning. */
function clearPrivateFeatures(): Promise<void> {
  const attempts = [clearShopCache, clearAnnouncementCache].map(clear => {
    try { return clear(); }
    catch (error) { return Promise.reject(error); }
  });
  return Promise.allSettled(attempts).then(results => {
    const failed = results.find(result => result.status === 'rejected');
    if (failed?.status === 'rejected') throw failed.reason;
  });
}

export function MobileProvider({ children }: { children: ReactNode }) {
  const system = useColorScheme();
  const [appearance, setAppearanceState] = useState<AppearanceMode>('system');
  const [appearanceReady, setAppearanceReady] = useState(false);
  const [session, setSession] = useState<Session | null>(null);
  const [identity, setIdentity] = useState<GymloopIdentity>({ kind: 'unlinked' });
  const [sessionReady, setSessionReady] = useState(false);
  const previousScope = useRef<string | null | undefined>(undefined);
  const published = useRef(false);
  const authRevision = useRef<object>({});
  const featureCleanup = useRef<Promise<void>>(Promise.resolve());
  const [businessValue, setBusinessValue] = useState<{ scope: string | null; type: BusinessType | null; hydrated: boolean }>({ scope: null, type: null, hydrated: false });
  const businessRevision = useRef<object>({});
  const businessStorage = useRef<Promise<void>>(Promise.resolve());
  const businessScope = identity.kind === 'member' || identity.kind === 'staff' ? `${identity.userId}:${identity.tenantId}` : null;
  const businessType = businessValue.scope === businessScope ? businessValue.type : null;
  const businessTenant = identity.kind === 'member' || identity.kind === 'staff' ? identity.tenantId : null;
  const [fontsLoaded] = useFonts({
    Archivo_400Regular, Archivo_500Medium, Archivo_600SemiBold, Archivo_700Bold,
    ArchivoDisplay: archivoDisplay, ArchivoDisplayBold: archivoDisplayBold,
  });

  const resolve = useCallback(async (nextSession: Session | null) => {
    const revision = {};
    authRevision.current = revision;
    businessRevision.current = {};
    setBusinessValue({ scope: null, type: null, hydrated: false });
    setIdentity({ kind: 'unlinked' });
    setSessionReady(false);
    if (published.current || nextSession === null) {
      const clearing = clearPrivateFeatures();
      featureCleanup.current = clearing;
      void clearing.catch(() => undefined);
    }
    const isCurrent = () => authRevision.current === revision;
    try {
      const startup = await resolveNativeMobileSession(supabase, nextSession, isCurrent);
      if (!isCurrent()) return;
      const nextIdentity: GymloopIdentity = startup.identity;
      const nextScope = scopeKey(nextIdentity);
      if (nextScope === null && previousScope.current === undefined && nextSession !== null) {
        featureCleanup.current = clearPrivateFeatures();
      }
      await featureCleanup.current;
      if (!isCurrent()) return;
      if (startup.replay !== 'deferred' && nextScope !== null) {
        if (previousScope.current !== undefined && previousScope.current !== nextScope) await clearOfflineCheckIns();
        if (!isCurrent()) return;
        previousScope.current = nextScope;
      }
      if (nextScope === null) previousScope.current = null;
      // A live unlinked session still supplies the viewer's own email for honest account recovery.
      setSession(nextSession);
      setIdentity(nextIdentity);
      published.current = true;
      setSessionReady(true);
    } catch {
      if (!isCurrent()) return;
      await clearPrivateFeatures().catch(() => undefined);
      if (!isCurrent()) return;
      // A failed privacy-critical queue cleanup cannot publish a new linked identity.
      authRevision.current = {};
      setSession(nextSession);
      setIdentity({ kind: 'unlinked' });
      published.current = true;
      setSessionReady(true);
    }
  }, []);

  useEffect(() => {
    void SecureStore.getItemAsync(APPEARANCE_KEY)
      .then((savedAppearance) => {
        if (savedAppearance === 'system' || savedAppearance === 'light' || savedAppearance === 'dark') setAppearanceState(savedAppearance);
      })
      .finally(() => setAppearanceReady(true));
    let authEventSeen = false;
    let mounted = true;
    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      authEventSeen = true;
      if (mounted) void resolve(nextSession);
    });
    void supabase.auth.getSession().then(({ data: snapshot }) => {
      if (mounted && !authEventSeen) return resolve(snapshot.session);
    }).catch(() => {
      if (mounted && !authEventSeen) return resolve(null);
    });
    return () => {
      mounted = false;
      authRevision.current = {};
      businessRevision.current = {};
      void clearPrivateFeatures().catch(() => undefined);
      data.subscription.unsubscribe();
    };
  }, [resolve]);

  useEffect(() => {
    const revision = {};
    businessRevision.current = revision;
    const isCurrent = () => businessRevision.current === revision;
    setBusinessValue({ scope: null, type: null, hydrated: false });
    // Serialize saves and deletion: an old save cannot follow a new sign-out delete.
    const persist = (type: BusinessType | null, tenantId?: string) => {
      businessStorage.current = businessStorage.current.catch(() => undefined).then(async () => {
        if (!isCurrent()) return;
        if (type === null || tenantId === undefined) await SecureStore.deleteItemAsync(BUSINESS_TYPE_STORAGE_KEY);
        else await SecureStore.setItemAsync(BUSINESS_TYPE_STORAGE_KEY, encodePersistedBusinessType(tenantId, type));
      }).catch(() => undefined);
      return businessStorage.current;
    };
    if (businessScope === null || businessTenant === null) {
      if (sessionReady) void persist(null);
      return () => { if (isCurrent()) businessRevision.current = {}; };
    }
    const tenantId = businessTenant;
    let known: BusinessType | null = null;
    let fetchRevision: object = {};
    const refresh = async () => {
      const fetchedRevision = {};
      fetchRevision = fetchedRevision;
      try {
        const { data, error } = await supabase.from('organizations').select('business_type').eq('id', tenantId).maybeSingle();
        if (!isCurrent() || fetchRevision !== fetchedRevision) return;
        const fetched = !error && isBusinessType(data?.business_type) ? data.business_type : null;
        known = resolveBusinessType({ fetched, persisted: known });
        setBusinessValue({ scope: businessScope, type: known, hydrated: true });
        if (fetched !== null) await persist(fetched, tenantId);
      } catch { /* Keep tenant-bound words while offline. */ }
    };
    const hydrate = async () => {
      try {
        const raw = await SecureStore.getItemAsync(BUSINESS_TYPE_STORAGE_KEY);
        if (!isCurrent()) return;
        known = readPersistedBusinessType(raw, tenantId);
      } catch { /* Cache failure uses the default nouns. */ }
      if (!isCurrent()) return;
      setBusinessValue({ scope: businessScope, type: known, hydrated: true });
      void refresh();
    };
    const hydration = hydrate();
    const subscription = AppState.addEventListener('change', (state) => { if (state === 'active' && isCurrent()) void hydration.then(refresh); });
    return () => { if (isCurrent()) businessRevision.current = {}; subscription.remove(); };
  }, [businessScope, businessTenant, sessionReady]);

  const setAppearance = useCallback(async (mode: AppearanceMode) => {
    await SecureStore.setItemAsync(APPEARANCE_KEY, mode);
    setAppearanceState(mode);
  }, []);
  const signOut = useCallback(async () => {
    authRevision.current = {};
    businessRevision.current = {};
    setBusinessValue({ scope: null, type: null, hydrated: false });
    setIdentity({ kind: 'unlinked' });
    const clearing = clearPrivateFeatures();
    businessStorage.current = businessStorage.current.catch(() => undefined).then(() => SecureStore.deleteItemAsync(BUSINESS_TYPE_STORAGE_KEY)).catch(() => undefined);
    try { await Promise.all([businessStorage.current, clearing]); }
    finally { await signOutMobile(supabase); }
  }, []);
  const api = useMemo(() => {
    const revision = authRevision.current;
    const isCurrent = () => authRevision.current === revision;
    return createApiClient({
      baseUrl: config.EXPO_PUBLIC_API_BASE_URL,
      accessToken: async () => {
        if (!isCurrent()) throw new Error('This session is no longer current.');
        const current = (await supabase.auth.getSession()).data.session;
        if (!isCurrent() || current?.user.id !== session?.user.id || current?.access_token !== session?.access_token) throw new Error('This session is no longer current.');
        return current?.access_token ?? null;
      },
      fetch: ((input, init) => {
        if (!isCurrent()) throw new Error('This session is no longer current.');
        return fetch(input, init);
      }) as ApiFetch,
    });
  }, [session, identity]);
  const resolvedAppearance = appearance === 'system' ? (system === 'dark' ? 'dark' : 'light') : appearance;
  const palette = UI_TOKENS.colors[resolvedAppearance];
  const businessReady = businessScope === null || (businessValue.scope === businessScope && businessValue.hydrated);
  const ready = appearanceReady && fontsLoaded && sessionReady && businessReady;
  useEffect(() => { if (ready) void SplashScreen.hideAsync(); }, [ready]);
  const value = useMemo<MobileContextValue>(() => ({
    api, appearance, identity, businessType, nouns: businessNouns(businessType), palette, ready,
    session, supabase, setAppearance, signOut,
    webOrigin: config.EXPO_PUBLIC_API_BASE_URL,
  }), [api, appearance, identity, businessType, palette, ready, session, setAppearance, signOut]);
  if (!ready) return null;
  return <MobileContext.Provider value={value}>
    <StatusBar
      backgroundColor={palette.canvas}
      barStyle={resolvedAppearance === 'dark' ? 'light-content' : 'dark-content'}
    />
    {children}
  </MobileContext.Provider>;
}

export function useMobile(): MobileContextValue {
  const value = useContext(MobileContext);
  if (value === null) throw new Error('MobileProvider is missing.');
  return value;
}
