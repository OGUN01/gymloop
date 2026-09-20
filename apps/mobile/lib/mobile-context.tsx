import { createApiClient, type ApiClient, type ApiFetch } from '@gymloop/api-client';
import { mobileClientEnv, type GymloopIdentity, UI_TOKENS } from '@gymloop/shared';
import { Inter_400Regular, Inter_500Medium, Inter_600SemiBold, Inter_700Bold, useFonts } from '@expo-google-fonts/inter';
import type { Session, SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import * as SecureStore from 'expo-secure-store';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar, useColorScheme } from 'react-native';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { clearOfflineCheckIns } from './offline-check-in';
import { createMobileSupabase, resolveNativeMobileSession, signOutMobile } from './native-session';

const APPEARANCE_KEY = 'gymloop.appearance';
export type AppearanceMode = 'system' | 'light' | 'dark';
type MobilePalette = (typeof UI_TOKENS.colors)[keyof typeof UI_TOKENS.colors];

type MobileContextValue = {
  api: ApiClient;
  appearance: AppearanceMode;
  identity: GymloopIdentity;
  palette: MobilePalette;
  ready: boolean;
  session: Session | null;
  supabase: SupabaseClient<Database>;
  setAppearance(mode: AppearanceMode): Promise<void>;
  signOut(): Promise<void>;
};

const MobileContext = createContext<MobileContextValue | null>(null);
void SplashScreen.preventAutoHideAsync().catch(() => undefined);
const config = mobileClientEnv();
const supabase = createMobileSupabase({
  supabaseUrl: config.EXPO_PUBLIC_SUPABASE_URL,
  supabaseAnonKey: config.EXPO_PUBLIC_SUPABASE_ANON_KEY,
});
const api = createApiClient({
  baseUrl: config.EXPO_PUBLIC_API_BASE_URL,
  accessToken: async () => (await supabase.auth.getSession()).data.session?.access_token ?? null,
  fetch: ((input, init) => fetch(input, init)) as ApiFetch,
});

function scopeKey(identity: GymloopIdentity): string | null {
  if (identity.kind === 'member') return `${identity.userId}:${identity.tenantId}:${identity.memberId}`;
  return null;
}

export function MobileProvider({ children }: { children: ReactNode }) {
  const system = useColorScheme();
  const [appearance, setAppearanceState] = useState<AppearanceMode>('system');
  const [appearanceReady, setAppearanceReady] = useState(false);
  const [session, setSession] = useState<Session | null>(null);
  const [identity, setIdentity] = useState<GymloopIdentity>({ kind: 'unlinked' });
  const [sessionReady, setSessionReady] = useState(false);
  const previousScope = useRef<string | null | undefined>(undefined);
  const [fontsLoaded] = useFonts({
    Inter_400Regular, Inter_500Medium, Inter_600SemiBold, Inter_700Bold,
  });

  const resolve = useCallback(async (nextSession: Session | null) => {
    const startup = nextSession === null
      ? { identity: { kind: 'unlinked' } as const, replay: 'blocked' as const }
      : await resolveNativeMobileSession(supabase, nextSession);
    const nextIdentity: GymloopIdentity = startup.identity;
    const nextScope = scopeKey(nextIdentity);
    if (startup.replay !== 'deferred') {
      if (previousScope.current !== undefined && previousScope.current !== nextScope) await clearOfflineCheckIns();
      previousScope.current = nextScope;
    }
    setSession(nextIdentity.kind === 'unlinked' ? null : nextSession);
    setIdentity(nextIdentity);
    setSessionReady(true);
  }, []);

  useEffect(() => {
    void SecureStore.getItemAsync(APPEARANCE_KEY)
      .then((savedAppearance) => {
        if (savedAppearance === 'system' || savedAppearance === 'light' || savedAppearance === 'dark') setAppearanceState(savedAppearance);
      })
      .finally(() => setAppearanceReady(true));
    void supabase.auth.getSession().then(({ data }) => resolve(data.session)).catch(() => resolve(null));
    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => { void resolve(nextSession); });
    return () => data.subscription.unsubscribe();
  }, [resolve]);

  const setAppearance = useCallback(async (mode: AppearanceMode) => {
    await SecureStore.setItemAsync(APPEARANCE_KEY, mode);
    setAppearanceState(mode);
  }, []);
  const signOut = useCallback(async () => await signOutMobile(supabase), []);
  const resolvedAppearance = appearance === 'system' ? (system === 'dark' ? 'dark' : 'light') : appearance;
  const palette = UI_TOKENS.colors[resolvedAppearance];
  const ready = appearanceReady && fontsLoaded && sessionReady;
  useEffect(() => { if (ready) void SplashScreen.hideAsync(); }, [ready]);
  const value = useMemo<MobileContextValue>(() => ({
    api, appearance, identity, palette, ready,
    session, supabase, setAppearance, signOut,
  }), [appearance, identity, palette, ready, session, setAppearance, signOut]);
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
