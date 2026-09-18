import { createApiClient, type ApiClient, type ApiFetch } from '@gymloop/api-client';
import { classifyIdentity, mobileClientEnv, type GymloopIdentity, type SupportedLocale, UI_TOKENS } from '@gymloop/shared';
import { Inter_400Regular, Inter_500Medium, Inter_600SemiBold, Inter_700Bold, useFonts } from '@expo-google-fonts/inter';
import { NotoSansDevanagari_400Regular, NotoSansDevanagari_500Medium, NotoSansDevanagari_600SemiBold, NotoSansDevanagari_700Bold } from '@expo-google-fonts/noto-sans-devanagari';
import type { Session, SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import * as SecureStore from 'expo-secure-store';
import { useColorScheme } from 'react-native';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { clearOfflineCheckIns } from './offline-check-in';
import { createMobileSupabase, signOutMobile } from './session';

const APPEARANCE_KEY = 'gymloop.appearance';
const LANGUAGE_KEY = 'gymloop.language';
export type AppearanceMode = 'system' | 'light' | 'dark';
export type MobilePalette = (typeof UI_TOKENS.colors)[keyof typeof UI_TOKENS.colors];

type MobileContextValue = {
  api: ApiClient;
  appearance: AppearanceMode;
  identity: GymloopIdentity;
  language: SupportedLocale;
  palette: MobilePalette;
  ready: boolean;
  session: Session | null;
  supabase: SupabaseClient<Database>;
  setAppearance(mode: AppearanceMode): Promise<void>;
  setLanguage(locale: SupportedLocale): Promise<void>;
  signOut(): Promise<void>;
};

const MobileContext = createContext<MobileContextValue | null>(null);
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
  if (identity.kind === 'member' || identity.kind === 'staff') return `${identity.userId}:${identity.tenantId}`;
  return null;
}

export function MobileProvider({ children }: { children: ReactNode }) {
  const system = useColorScheme();
  const [appearance, setAppearanceState] = useState<AppearanceMode>('system');
  const [language, setLanguageState] = useState<SupportedLocale>('en');
  const [session, setSession] = useState<Session | null>(null);
  const [identity, setIdentity] = useState<GymloopIdentity>({ kind: 'unlinked' });
  const [sessionReady, setSessionReady] = useState(false);
  const previousScope = useRef<string | null | undefined>(undefined);
  const [fontsLoaded] = useFonts({
    Inter_400Regular, Inter_500Medium, Inter_600SemiBold, Inter_700Bold,
    NotoSansDevanagari_400Regular, NotoSansDevanagari_500Medium,
    NotoSansDevanagari_600SemiBold, NotoSansDevanagari_700Bold,
  });

  const resolve = useCallback(async (nextSession: Session | null) => {
    let nextIdentity: GymloopIdentity = { kind: 'unlinked' };
    if (nextSession !== null) {
      const verified = await supabase.auth.getClaims(nextSession.access_token);
      if (!verified.error && verified.data?.claims.role === 'authenticated') {
        const classified = classifyIdentity(verified.data.claims);
        if (classified.kind !== 'unlinked' && classified.userId === nextSession.user.id) nextIdentity = classified;
      }
    }
    const nextScope = scopeKey(nextIdentity);
    if (previousScope.current !== undefined && previousScope.current !== nextScope) await clearOfflineCheckIns();
    previousScope.current = nextScope;
    setSession(nextIdentity.kind === 'unlinked' ? null : nextSession);
    setIdentity(nextIdentity);
    setSessionReady(true);
  }, []);

  useEffect(() => {
    void Promise.all([SecureStore.getItemAsync(APPEARANCE_KEY), SecureStore.getItemAsync(LANGUAGE_KEY)])
      .then(([savedAppearance, savedLanguage]) => {
        if (savedAppearance === 'system' || savedAppearance === 'light' || savedAppearance === 'dark') setAppearanceState(savedAppearance);
        if (savedLanguage === 'en' || savedLanguage === 'hi') setLanguageState(savedLanguage);
      });
    void supabase.auth.getSession().then(({ data }) => resolve(data.session));
    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => { void resolve(nextSession); });
    return () => data.subscription.unsubscribe();
  }, [resolve]);

  const setAppearance = useCallback(async (mode: AppearanceMode) => {
    await SecureStore.setItemAsync(APPEARANCE_KEY, mode);
    setAppearanceState(mode);
  }, []);
  const setLanguage = useCallback(async (locale: SupportedLocale) => {
    await SecureStore.setItemAsync(LANGUAGE_KEY, locale);
    setLanguageState(locale);
  }, []);
  const signOut = useCallback(async () => await signOutMobile(supabase), []);
  const resolvedAppearance = appearance === 'system' ? (system === 'dark' ? 'dark' : 'light') : appearance;
  const palette = UI_TOKENS.colors[resolvedAppearance];
  const value = useMemo<MobileContextValue>(() => ({
    api, appearance, identity, language, palette, ready: fontsLoaded && sessionReady,
    session, supabase, setAppearance, setLanguage, signOut,
  }), [appearance, fontsLoaded, identity, language, palette, session, sessionReady, setAppearance, setLanguage, signOut]);
  return <MobileContext.Provider value={value}>{children}</MobileContext.Provider>;
}

export function useMobile(): MobileContextValue {
  const value = useContext(MobileContext);
  if (value === null) throw new Error('MobileProvider is missing.');
  return value;
}
