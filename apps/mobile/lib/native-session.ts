import * as SecureStore from 'expo-secure-store';
import {
  createClient,
  isAuthRetryableFetchError,
  processLock,
  type Session,
  type SupabaseClient,
} from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import { classifyIdentity, type GymloopIdentity } from '@gymloop/shared';
import { clearOfflineCheckIns } from './offline-check-in';
import { savePendingInvite } from './invite';
import { resolveMobileStartup, type MobileStartupRefresh, type MobileStartupState } from './session';

const SESSION_KEY = 'gymloop.session';
const IDENTITY_KEY = 'gymloop.authenticated-identity';
type MobileConfig = { supabaseUrl: string; supabaseAnonKey: string; apiBaseUrl: string };
type LinkedIdentity = Exclude<GymloopIdentity, { kind: 'unlinked' }>;
const MOBILE_GOOGLE_CALLBACK = 'fitcruxx://auth/callback';
const MOBILE_GOOGLE_CALLBACK_URL = new URL(MOBILE_GOOGLE_CALLBACK);

type MobileGoogleSupabase = {
  auth: {
    signInWithOAuth: (options: {
      provider: 'google';
      options: { redirectTo: string; skipBrowserRedirect: true; queryParams: { prompt: 'select_account' } };
    }) => Promise<{ data: { url: string | null }; error: unknown }>;
    exchangeCodeForSession: (code: string) => Promise<{ data: unknown; error: unknown }>;
  };
};

type MobileGoogleBrowser = (url: string, callback: string) => Promise<{ type: string; url?: string }>;

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
  let storageAvailable = true;
  try {
    const saved = await SecureStore.getItemAsync(IDENTITY_KEY);
    if (saved !== null) {
      let cached: LinkedIdentity | null = null;
      try { cached = linkedIdentity(JSON.parse(saved), session.user.id); } catch { cached = null; }
      if (cached !== null) return cached;
    }
  } catch {
    // A missing optional cache may fall back only to this authenticated session's same-user JWT.
    storageAvailable = false;
  }

  // Continuity for sessions created before the dedicated identity cache. These
  // facts came inside a prior authenticated session in encrypted app storage.
  // Decoded token facts scope local offline UI only; they never authorize an
  // API request, whose bearer signature and RLS are still checked remotely.
  if (storageAvailable) {
    const metadataIdentity = classifyIdentity({ ...session.user.app_metadata, sub: session.user.id });
    if (metadataIdentity.kind !== 'unlinked' && metadataIdentity.userId === session.user.id) return metadataIdentity;
  }
  const tokenIdentity = classifyIdentity(claimsFromPersistedToken(session.access_token));
  return tokenIdentity.kind === 'unlinked' || tokenIdentity.userId !== session.user.id ? null : tokenIdentity;
}

async function writeCachedIdentity(identity: LinkedIdentity): Promise<void> {
  try { await SecureStore.setItemAsync(IDENTITY_KEY, JSON.stringify(identity)); } catch {
    // Optional offline continuity cannot veto an already verified online identity.
  }
}

// Auth/PKCE bytes are privacy-critical and use a separate device queue from optional identity metadata.
let authStorageWrites: Promise<void> = Promise.resolve();
let authStorageRevision: object = {};
const authStorageKeyRevisions = new Map<string, object>();

function queueAuthStorage(operation: () => Promise<void>): Promise<void> {
  const pending = authStorageWrites.then(operation);
  // Subsequent cleanup remains usable after a failure; the caller still receives the critical rejection.
  authStorageWrites = pending.then(() => undefined, () => undefined);
  return pending;
}

async function readAuthStorage(key: string): Promise<string | null> {
  while (true) {
    const writes = authStorageWrites;
    await writes;
    if (writes !== authStorageWrites) continue;
    const revision = authStorageRevision;
    const keyRevision = authStorageKeyRevisions.get(key);
    const stored = await SecureStore.getItemAsync(`${SESSION_KEY}.${key}`);
    if (revision === authStorageRevision && keyRevision === authStorageKeyRevisions.get(key)
      && writes === authStorageWrites) return stored;
  }
}

function writeAuthStorage(key: string, value: string): Promise<void> {
  const revision = authStorageRevision;
  const keyRevision = {};
  authStorageKeyRevisions.set(key, keyRevision);
  const isCurrent = () => revision === authStorageRevision && keyRevision === authStorageKeyRevisions.get(key);
  return queueAuthStorage(async () => {
    if (!isCurrent()) return;
    try { await SecureStore.setItemAsync(`${SESSION_KEY}.${key}`, value); }
    finally {
      // A write may physically finish after another client removed this key or began logout.
      if (!isCurrent()) await SecureStore.deleteItemAsync(`${SESSION_KEY}.${key}`);
    }
  });
}

function removeAuthStorage(key: string): Promise<void> {
  authStorageKeyRevisions.set(key, {});
  return queueAuthStorage(() => SecureStore.deleteItemAsync(`${SESSION_KEY}.${key}`));
}

/** Native Auth client: only public credentials and encrypted device persistence. */
export function createMobileSupabase(config: Pick<MobileConfig, 'supabaseUrl' | 'supabaseAnonKey'>) {
  return createClient<Database>(config.supabaseUrl, config.supabaseAnonKey, {
    auth: {
      storage: { getItem: readAuthStorage, setItem: writeAuthStorage, removeItem: removeAuthStorage },
      // The SDK holds this device-wide lock through refresh/PKCE responses and logout cleanup.
      lock: processLock,
      persistSession: true, autoRefreshToken: true, detectSessionInUrl: false, flowType: 'pkce',
    },
  });
}

/** Opens the fixed Google callback and exchanges only its PKCE authorization code. */
export async function signInWithGoogleMobile(input: {
  supabase: MobileGoogleSupabase;
  openBrowser: MobileGoogleBrowser;
}): Promise<{ ok: true } | { ok: false }> {
  try {
    const { data, error } = await input.supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: MOBILE_GOOGLE_CALLBACK, skipBrowserRedirect: true, queryParams: { prompt: 'select_account' } },
    });
    if (error || data.url === null) return { ok: false };

    const browserResult = await input.openBrowser(data.url, MOBILE_GOOGLE_CALLBACK);
    if (browserResult.type !== 'success' || browserResult.url === undefined) return { ok: false };

    const code = mobileGoogleCallbackCode(browserResult.url);
    if (code === null) return { ok: false };
    return await exchangeMobileGoogleCode({ supabase: input.supabase, code });
  } catch {
    return { ok: false };
  }
}

type NativeSessionWork = { revision: object; cacheWrites: Promise<void> };
// IDENTITY_KEY is device-wide, so every Auth client must share its ordering and write queue.
const nativeSessionWork: NativeSessionWork = { revision: {}, cacheWrites: Promise.resolve() };

/** All claims/cache work on this device shares one order, including explicit sign-out. */
function beginNativeSessionWork() {
  const work = nativeSessionWork;
  const revision = {};
  work.revision = revision;
  return { work, revision };
}

/** Serialize optional persistence; clean a physically late obsolete write before the next write. */
function persistNativeIdentity(work: NativeSessionWork, revision: object, identity: LinkedIdentity | null, isCurrent: () => boolean) {
  work.cacheWrites = work.cacheWrites.then(async () => {
    if (work.revision !== revision || !isCurrent()) return;
    try {
      if (identity === null) await SecureStore.deleteItemAsync(IDENTITY_KEY);
      else await writeCachedIdentity(identity);
      if (work.revision !== revision || !isCurrent()) await SecureStore.deleteItemAsync(IDENTITY_KEY);
    } catch {
      // This cache is optional. Claims resolution and authoritative sign-out remain independent of it.
    }
  });
}

/** One account-switch press: persist consent context, end the session, then open Google's chooser. */
export async function switchNativeInviteAccount(input: Parameters<typeof signInWithGoogleMobile>[0] & {
  token: string;
  signOut: () => Promise<void>;
}): Promise<{ ok: true } | { ok: false }> {
  await savePendingInvite(input.token);
  await input.signOut();
  return signInWithGoogleMobile(input);
}

/**
 * The one registered native callback. A URL is accepted only if it is exactly
 * that callback carrying a non-empty PKCE code; anything else (including the
 * retired scheme of older test installs) fails generically.
 */
function mobileGoogleCallbackCode(url: string): string | null {
  try {
    const callback = new URL(url);
    if (callback.protocol !== MOBILE_GOOGLE_CALLBACK_URL.protocol
      || callback.hostname !== MOBILE_GOOGLE_CALLBACK_URL.hostname
      || callback.pathname !== MOBILE_GOOGLE_CALLBACK_URL.pathname) return null;
    const code = callback.searchParams.get('code');
    return code === null || code === '' ? null : code;
  } catch {
    return null;
  }
}

const googleCodeExchanges = new Map<string, Promise<{ ok: boolean }>>();

/**
 * PKCE codes are single-use, and two surfaces see the same one: the auth-session
 * result and the `fitcruxx://auth/callback` route. Both callers share a single
 * exchange per code, so the code is never spent twice and both observe one
 * generic ok/fail outcome. The memo also means a duplicate delivery of the same
 * deep link cannot re-exchange a code that is already spent.
 */
export function exchangeMobileGoogleCode(input: {
  supabase: { auth: { exchangeCodeForSession: (code: string) => Promise<{ data: unknown; error: unknown }> } };
  code: string;
}): Promise<{ ok: boolean }> {
  const existing = googleCodeExchanges.get(input.code);
  if (existing !== undefined) return existing;
  const attempt = input.supabase.auth.exchangeCodeForSession(input.code)
    .then((exchanged) => ({ ok: exchanged.error === null }))
    .catch(() => ({ ok: false }));
  googleCodeExchanges.set(input.code, attempt);
  return attempt;
}

/**
 * What the callback route shows. The resolved values never carry the code: a
 * live session means the exchange already happened (redirect home), a missing
 * code or a failed exchange is the one generic failure, otherwise keep the
 * existing loading state while the session resolves.
 */
export function resolveMobileGoogleCallbackState(input: {
  code: string | null;
  hasSession: boolean;
  exchangeFailed: boolean;
}): { kind: 'redirect' } | { kind: 'loading' } | { kind: 'failed' } {
  if (input.hasSession) return { kind: 'redirect' };
  if (input.code === null || input.exchangeFailed) return { kind: 'failed' };
  return { kind: 'loading' };
}

/** Resolve remote claims when possible and defer, rather than erase, offline work on transient failure. */
export async function resolveNativeMobileSession(
  supabase: SupabaseClient<Database>,
  session: Session | null,
  isCurrent: () => boolean = () => true,
): Promise<MobileStartupState> {
  const { work, revision } = beginNativeSessionWork();
  if (session === null) {
    persistNativeIdentity(work, revision, null, isCurrent);
    return resolveMobileStartup({ cachedIdentity: null, refresh: { kind: 'invalid' } });
  }
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
  // Fresh claims are authoritative. Read the optional continuity cache only when verification is offline.
  let cachedIdentity: LinkedIdentity | null = null;
  if (refresh.kind === 'network_error') {
    await work.cacheWrites;
    if (work.revision === revision && isCurrent()) cachedIdentity = await readCachedIdentity(session);
  }
  const startup = resolveMobileStartup({ cachedIdentity, refresh });
  if (work.revision !== revision || !isCurrent()) return resolveMobileStartup({ cachedIdentity: null, refresh: { kind: 'invalid' } });
  const cache = refresh.kind === 'verified' && startup.identity.kind !== 'unlinked' ? startup.identity : cachedIdentity;
  persistNativeIdentity(work, revision, cache, isCurrent);
  return startup;
}

/** Sign-out clears private queued commands and local identity before removing Auth tokens. */
export async function signOutMobile(supabase: SupabaseClient<Database>): Promise<void> {
  const { work, revision } = beginNativeSessionWork();
  authStorageRevision = {};
  googleCodeExchanges.clear();
  const cleanup = await Promise.resolve().then(() => clearOfflineCheckIns()).then(
    () => ({ ok: true as const }),
    (error: unknown) => ({ ok: false as const, error }),
  );
  persistNativeIdentity(work, revision, null, () => true);
  const result = await supabase.auth.signOut();
  if (result.error) throw result.error;
  if (!cleanup.ok) throw cleanup.error;
}
