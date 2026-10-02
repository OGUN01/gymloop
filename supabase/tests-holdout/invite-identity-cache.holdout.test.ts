// Independent native continuity / INV-022 fresh-claims contract. Public interface only;
// native implementation and other authors' tests remain unread.
import { AuthRetryableFetchError } from '@supabase/supabase-js';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const cache = vi.hoisted(() => ({ read: vi.fn(), write: vi.fn(), remove: vi.fn() }));
vi.mock('expo-secure-store', () => ({
  getItemAsync: cache.read, setItemAsync: cache.write, deleteItemAsync: cache.remove,
}));
vi.mock('expo-web-browser', () => ({ maybeCompleteAuthSession: vi.fn(), openAuthSessionAsync: vi.fn() }));
vi.mock('react-native', () => ({
  Platform: { OS: 'android', select: (options: any) => options.android ?? options.default },
  AppState: { currentState: 'active', addEventListener: () => ({ remove: vi.fn() }) },
  Linking: { createURL: (path: string) => `fitcruxx://${path}` },
}));

const fixture = {
  cacheKey: 'gymloop.authenticated-identity',
  user: '1a111111-1111-4111-8111-111111111111',
  tenant: '2b222222-2222-4222-8222-222222222222',
  member: '3c333333-3333-4333-8333-333333333333',
  staleUser: '4d444444-4444-4444-8444-444444444444',
  staleMember: '5e555555-5555-4555-8555-555555555555',
};
const fresh = { kind: 'member', userId: fixture.user, tenantId: fixture.tenant, memberId: fixture.member };
const stale = { kind: 'member', userId: fixture.staleUser, tenantId: fixture.tenant, memberId: fixture.staleMember };
const session = {
  // Deliberately opaque: an offline test must not acquire identity from an unverified
  // JWT fallback. Online getClaims is the authority, and is mocked as verified below.
  access_token: 'opaque-public-auth-session-for-independent-holdout', refresh_token: 'opaque-refresh',
  expires_in: 3600, token_type: 'bearer',
  user: { id: fixture.user, aud: 'authenticated', role: 'authenticated',
    email: 'fresh-member@holdout.example', app_metadata: {}, user_metadata: {}, created_at: '2026-10-02T00:00:00Z' },
};
let claims: any;
let supabase: any;

beforeEach(() => {
  vi.stubEnv('EXPO_PUBLIC_SUPABASE_URL', 'https://independent-cache.supabase.co');
  vi.stubEnv('EXPO_PUBLIC_SUPABASE_ANON_KEY', 'independent-public-anon-key');
  cache.read.mockReset().mockResolvedValue(null);
  cache.write.mockReset().mockResolvedValue(undefined);
  cache.remove.mockReset().mockResolvedValue(undefined);
  claims = { data: { claims: { role: 'authenticated', sub: fixture.user,
    app_role: 'member', tenant_id: fixture.tenant, member_id: fixture.member } }, error: null };
  supabase = { auth: {
    getClaims: vi.fn(async () => claims),
    getSession: vi.fn(async () => ({ data: { session }, error: null })),
    getUser: vi.fn(async () => ({ data: { user: session.user }, error: null })),
    refreshSession: vi.fn(async () => ({ data: { session }, error: null })),
  } };
});
afterEach(() => vi.unstubAllEnvs());

async function resolve() {
  const { resolveNativeMobileSession } = await import('../../apps/mobile/lib/native-session');
  return resolveNativeMobileSession(supabase, session as any);
}
function cacheFailure() { return new Error('Independent optional identity-cache I/O unavailable'); }

describe('INV-022 verified native claims survive optional identity-cache failure', () => {
  it.each(['read', 'write', 'both'])('verified online member resolves fresh ready state when cache %s fails', async operation => {
    if (operation !== 'write') cache.read.mockRejectedValue(cacheFailure());
    if (operation !== 'read') cache.write.mockRejectedValue(cacheFailure());
    await expect(resolve()).resolves.toEqual({ identity: fresh,
      queueScope: { userId: fixture.user, tenantId: fixture.tenant, memberId: fixture.member }, replay: 'ready' });
    expect(supabase.auth.getClaims).toHaveBeenCalledWith(session.access_token);
  });
  it('fresh online claims override another user cached identity even when writing the fresh cache fails', async () => {
    cache.read.mockImplementation(async (key: string) => key === fixture.cacheKey ? JSON.stringify(stale) : null);
    cache.write.mockRejectedValue(cacheFailure());
    await expect(resolve()).resolves.toEqual({ identity: fresh,
      queueScope: { userId: fixture.user, tenantId: fixture.tenant, memberId: fixture.member }, replay: 'ready' });
  });
  it('fresh online member association overrides stale same-user member association despite cache write failure', async () => {
    cache.read.mockResolvedValue(JSON.stringify({ ...stale, userId: fixture.user }));
    cache.write.mockRejectedValue(cacheFailure());
    const result = await resolve();
    expect(result.identity).toEqual(fresh); expect(result.queueScope?.memberId).toBe(fixture.member);
    expect(result.queueScope?.memberId).not.toBe(fixture.staleMember); expect(result.replay).toBe('ready');
  });
  it.each(['read-error', 'corrupt-cache', 'wrong-user-cache'])('offline %s without verified identity claims resolves safely without false member scope', async condition => {
    claims = { data: { claims: null }, error: new AuthRetryableFetchError('Independent offline verifier', 503) };
    if (condition === 'read-error') cache.read.mockRejectedValue(cacheFailure());
    else cache.read.mockResolvedValue(condition === 'corrupt-cache' ? '{not-valid-cached-identity' : JSON.stringify(stale));
    cache.write.mockRejectedValue(cacheFailure());
    let result: any;
    await expect(resolve().then(value => { result = value; })).resolves.toBeUndefined();
    expect(result.identity.kind).toBe('unlinked');
    expect(result.queueScope).toBeNull(); expect(['deferred', 'blocked']).toContain(result.replay);
  });
});

describe('native identity-cache ordering is shared across distinct public clients', () => {
  function gate<T>() {
    let resolve!: (value: T) => void;
    const promise = new Promise<T>(done => { resolve = done; });
    return { promise, resolve };
  }
  async function settle() { for (let step = 0; step < 20; step++) await Promise.resolve(); }
  function raceSetup() {
    const storage = new Map<string, string>();
    cache.read.mockImplementation(async (key: string) => storage.get(key) ?? null);
    cache.write.mockImplementation(async (key: string, value: string) => { storage.set(key, value); });
    cache.remove.mockImplementation(async (key: string) => { storage.delete(key); });
    const sessionB = { ...session, access_token: 'second-client-verified-token',
      user: { ...session.user, id: fixture.staleUser } };
    const identityB = { kind: 'member', userId: fixture.staleUser, tenantId: fixture.tenant, memberId: fixture.staleMember };
    const clientA = { auth: { getClaims: vi.fn(async () => claims), signOut: vi.fn(async () => ({ error: null })) } };
    const clientB = { auth: { getClaims: vi.fn(async () => ({ data: { claims: {
      role: 'authenticated', sub: fixture.staleUser, app_role: 'member', tenant_id: fixture.tenant, member_id: fixture.staleMember,
    } }, error: null })), signOut: vi.fn(async () => ({ error: null })) } };
    return { storage, sessionB, identityB, clientA, clientB };
  }
  it('older claims on client A cannot recreate cache after client B signs out', async () => {
    const { resolveNativeMobileSession, signOutMobile } = await import('../../apps/mobile/lib/native-session');
    const { storage, clientA, clientB } = raceSetup(); const older = gate<any>();
    clientA.auth.getClaims.mockImplementation(() => older.promise);
    const oldResolution = resolveNativeMobileSession(clientA as any, session as any);
    await settle(); await signOutMobile(clientB as any);
    older.resolve(claims); await oldResolution; await settle();
    expect(clientB.auth.signOut).toHaveBeenCalledOnce();
    expect(storage.has(fixture.cacheKey)).toBe(false);
    expect(cache.remove.mock.calls.some(([key]: any[]) => key !== fixture.cacheKey)).toBe(true);
  });
  it('older claims on client A cannot replace the newer verified identity stored by client B', async () => {
    const { resolveNativeMobileSession } = await import('../../apps/mobile/lib/native-session');
    const { storage, clientA, clientB, sessionB, identityB } = raceSetup(); const older = gate<any>();
    clientA.auth.getClaims.mockImplementation(() => older.promise);
    const oldResolution = resolveNativeMobileSession(clientA as any, session as any); await settle();
    const current = await resolveNativeMobileSession(clientB as any, sessionB as any);
    expect(current.identity).toEqual(identityB); expect(current.replay).toBe('ready');
    older.resolve(claims); await oldResolution; await settle();
    expect(JSON.parse(storage.get(fixture.cacheKey)!)).toEqual(identityB);
  });
  it.each(['sign-out', 'newer-identity'])('a physically deferred client A write cannot undo client B %s', async operation => {
    const { resolveNativeMobileSession, signOutMobile } = await import('../../apps/mobile/lib/native-session');
    const { storage, clientA, clientB, sessionB, identityB } = raceSetup(); const write = gate<void>();
    cache.write.mockImplementation(async (key: string, value: string) => {
      if (key === fixture.cacheKey && JSON.parse(value).userId === fixture.user) await write.promise;
      storage.set(key, value);
    });
    const oldResolution = resolveNativeMobileSession(clientA as any, session as any); await settle();
    expect(cache.write.mock.calls.some(([key]: any[]) => key === fixture.cacheKey)).toBe(true);
    const current = operation === 'sign-out' ? signOutMobile(clientB as any)
      : resolveNativeMobileSession(clientB as any, sessionB as any);
    await settle(); write.resolve(); await Promise.all([oldResolution, current]); await settle();
    if (operation === 'sign-out') {
      expect(clientB.auth.signOut).toHaveBeenCalledOnce(); expect(storage.has(fixture.cacheKey)).toBe(false);
      expect(cache.remove.mock.calls.some(([key]: any[]) => key !== fixture.cacheKey)).toBe(true);
    } else expect(JSON.parse(storage.get(fixture.cacheKey)!)).toEqual(identityB);
  });
});
