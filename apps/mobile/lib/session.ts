import * as SecureStore from 'expo-secure-store';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import { clearOfflineCheckIns } from './offline-check-in';

const SESSION_KEY = 'gymloop.session';
type MobileConfig = { supabaseUrl: string; supabaseAnonKey: string; apiBaseUrl: string };

/** Native Auth client: only public credentials and encrypted device persistence. */
export function createMobileSupabase(config: Pick<MobileConfig, 'supabaseUrl' | 'supabaseAnonKey'>) {
  return createClient<Database>(config.supabaseUrl, config.supabaseAnonKey, {
    auth: {
      storage: { getItem: (key) => SecureStore.getItemAsync(`${SESSION_KEY}.${key}`), setItem: (key, value) => SecureStore.setItemAsync(`${SESSION_KEY}.${key}`, value), removeItem: (key) => SecureStore.deleteItemAsync(`${SESSION_KEY}.${key}`) },
      persistSession: true, autoRefreshToken: true, detectSessionInUrl: false,
    },
  });
}
/** Sign-out clears private queued commands, then delegates token removal to Auth's own adapter. */
export async function signOutMobile(supabase: SupabaseClient<Database>): Promise<void> {
  await clearOfflineCheckIns();
  await supabase.auth.signOut();
}
