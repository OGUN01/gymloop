import * as SecureStore from 'expo-secure-store';
import {
  createClient,
  isAuthRetryableFetchError,
  type Session,
  type SupabaseClient,
} from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import { classifyIdentity, type GymloopIdentity } from '@gymloop/shared';
import { clearOfflineCheckIns } from './offline-check-in';
import { resolveMobileStartup, type MobileStartupRefresh, type MobileStartupState } from './session';

const SESSION_KEY = 'gymloop.session';
const IDENTITY_KEY = 'gymloop.authenticated-identity';
type MobileConfig = { supabaseUrl: string; supabaseAnonKey: string; apiBaseUrl: string };
type LinkedIdentity = Exclude<GymloopIdentity, { kind: 'unlinked' }>;

function claimsForIdentity(value: unknown): unknown {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  const identity = value as Record<string, unknown>;
  if (identity.kind === 'member') return { sub: identity.userId, app_role: 'member', tenant_id: identity.tenantId, member_id: identity.memberId };
  if (identity.kind === 'staff') return { sub: identity.userId, app_role: identity.role, tenant_id: identity.tenantId, staff_id: identity.staffId };
  if (identity.kind === 'platform') return { sub: identity.userId, app_role: identity.role };
  if (identity.kind === 'impersonation') return { sub: identity.userId, app_role: 'gym_owner', tenant_id: identity.tenantId, impersonation_session_id: identity.impersonationSessionId };
  return null;
}

function linkedIdentity(value: unknown, userId: string): LinkedIdentity | null {
  const identity = classifyIdentity(claimsForIdentity(value));
  return identity.kind !== 'unlinked' && identity.userId === userId ? identity : null;
}

function claimsFromPersistedToken(token: string): unknown {
  const encoded = token.split('.')[1];
  if (encoded === undefined) return null;
  const base64 = encoded.replaceAll('-', '+').replaceAll('_', '/');
  const quantum = '===='.length;
  const remainder = base64.length % quantum;
  const padded = remainder === 0 ? base64 : base64.padEnd(base64.length + quantum - remainder, '=');
  try { return JSON.parse(globalThis.atob(padded)) as unknown; } catch { return null; }
}

async function readCachedIdentity(session: Session): Promise<LinkedIdentity | null> {
  const saved = await SecureStore.getItemAsync(IDENTITY_KEY);
  if (saved !== null) {
    try {
      const cached = linkedIdentity(JSON.parse(saved), session.user.id);
      if (cached !== null) return cached;
      await SecureStore.deleteItemAsync(IDENTITY_KEY);
    } catch {
      await SecureStore.deleteItemAsync(IDENTITY_KEY);
    }
  }

  // Continuity for sessions created before the dedicated identity cache. These
  // facts came inside a prior authenticated session in encrypted app storage.
  // Decoded token facts scope local offline UI only; they never authorize an
  // API request, whose bearer signature and RLS are still checked remotely.
  const metadataIdentity = classifyIdentity({ ...session.user.app_metadata, sub: session.user.id });
  if (metadataIdentity.kind !== 'unlinked' && metadataIdentity.userId === session.user.id) return metadataIdentity;
  const tokenIdentity = classifyIdentity(claimsFromPersistedToken(session.access_token));
  return tokenIdentity.kind === 'unlinked' || tokenIdentity.userId !== session.user.id ? null : tokenIdentity;
}

async function writeCachedIdentity(identity: LinkedIdentity): Promise<void> {
  await SecureStore.setItemAsync(IDENTITY_KEY, JSON.stringify(identity));
}

/** Native Auth client: only public credentials and encrypted device persistence. */
export function createMobileSupabase(config: Pick<MobileConfig, 'supabaseUrl' | 'supabaseAnonKey'>) {
  return createClient<Database>(config.supabaseUrl, config.supabaseAnonKey, {
    auth: {
      storage: { getItem: (key) => SecureStore.getItemAsync(`${SESSION_KEY}.${key}`), setItem: (key, value) => SecureStore.setItemAsync(`${SESSION_KEY}.${key}`, value), removeItem: (key) => SecureStore.deleteItemAsync(`${SESSION_KEY}.${key}`) },
      persistSession: true, autoRefreshToken: true, detectSessionInUrl: false,
    },
  });
}

/** Resolve remote claims when possible and defer, rather than erase, offline work on transient failure. */
export async function resolveNativeMobileSession(
  supabase: SupabaseClient<Database>,
  session: Session,
): Promise<MobileStartupState> {
  const cachedIdentity = await readCachedIdentity(session);
  let refresh: MobileStartupRefresh = { kind: 'invalid' };
  try {
    const verified = await supabase.auth.getClaims(session.access_token);
    if (verified.data?.claims.role === 'authenticated') {
      const identity = classifyIdentity(verified.data.claims);
      refresh = identity.kind !== 'unlinked' && identity.userId === session.user.id
        ? { kind: 'verified', identity }
        : { kind: 'invalid' };
    } else if (isAuthRetryableFetchError(verified.error)) refresh = { kind: 'network_error' };
  } catch (error) {
    refresh = isAuthRetryableFetchError(error) ? { kind: 'network_error' } : { kind: 'invalid' };
  }
  const startup = resolveMobileStartup({ cachedIdentity, refresh });
  if (refresh.kind === 'verified' && startup.identity.kind !== 'unlinked') await writeCachedIdentity(startup.identity);
  else if (refresh.kind === 'network_error' && cachedIdentity !== null) await writeCachedIdentity(cachedIdentity);
  else if (refresh.kind === 'invalid') await SecureStore.deleteItemAsync(IDENTITY_KEY);
  return startup;
}

/** Sign-out clears private queued commands and local identity before removing Auth tokens. */
export async function signOutMobile(supabase: SupabaseClient<Database>): Promise<void> {
  await clearOfflineCheckIns();
  await SecureStore.deleteItemAsync(IDENTITY_KEY);
  await supabase.auth.signOut();
}
