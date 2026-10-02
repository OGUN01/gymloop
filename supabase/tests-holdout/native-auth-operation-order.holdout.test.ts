// Independent HARD-011 regression using the installed, unmocked Supabase Auth SDK.
// Only transport and native platform/storage I/O are mocked. Project source unread.
import { Buffer } from 'node:buffer';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const io = vi.hoisted(() => ({ bytes: new Map<string, string>(), fetch: vi.fn(), clients: [] as any[] }));
vi.mock('expo-secure-store', () => ({
  getItemAsync: async (key: string) => io.bytes.get(key) ?? null,
  setItemAsync: async (key: string, value: string) => { io.bytes.set(key, value); },
  deleteItemAsync: async (key: string) => { io.bytes.delete(key); },
}));
vi.mock('expo-web-browser', () => ({ maybeCompleteAuthSession: vi.fn(), openAuthSessionAsync: vi.fn() }));
vi.mock('react-native', () => ({
  Platform: { OS: 'android', select: (options: any) => options.android ?? options.default },
  AppState: { currentState: 'active', addEventListener: () => ({ remove: vi.fn() }) },
  Linking: { createURL: (path: string) => `fitcruxx://${path}` },
}));

const fixture = {
  origin: 'https://operation-order.supabase.co', anonKey: 'public-operation-order-key',
  userId: '8a111111-1111-4111-8111-111111111111',
  sdkKey: 'sb-operation-order-auth-token', durableKey: 'gymloop.session.sb-operation-order-auth-token',
};
function gate<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve };
}
async function settle() { for (let step = 0; step < 32; step++) await Promise.resolve(); }
function accessToken(tag: string) {
  const encode = (value: any) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ aud: 'authenticated', role: 'authenticated', sub: fixture.userId,
    exp: Math.floor(Date.now() / 1000) + 3600, independent_fixture: tag })}.${Buffer.from('synthetic-signature').toString('base64url')}`;
}
function tokenResponse(tag: string) {
  return { access_token: accessToken(tag), refresh_token: `refresh-${tag}`, expires_in: 3600, token_type: 'bearer',
    user: { id: fixture.userId, aud: 'authenticated', role: 'authenticated',
      email: 'sdk-only@holdout.example', app_metadata: { provider: 'google', providers: ['google'] },
      user_metadata: {}, identities: [], created_at: '2026-10-02T00:00:00Z' } };
}
function response(tag: string) {
  return new Response(JSON.stringify(tokenResponse(tag)), { status: 200, headers: { 'Content-Type': 'application/json' } });
}
async function realClient(native: any) {
  const client = native.createMobileSupabase({ supabaseUrl: fixture.origin, supabaseAnonKey: fixture.anonKey });
  io.clients.push(client);
  // Stop only public SDK background refresh; these tests control explicit operations.
  await client.auth.stopAutoRefresh(); await client.auth.getSession(); return client;
}

beforeEach(() => {
  io.bytes.clear(); io.clients = []; io.fetch.mockReset();
  io.fetch.mockImplementation(async (input: any) => {
    const url = new URL(typeof input === 'string' ? input : input.url);
    if (url.pathname.endsWith('/logout')) return new Response(null, { status: 204 });
    if (url.pathname.endsWith('/user')) return new Response(JSON.stringify(tokenResponse('user').user),
      { status: 200, headers: { 'Content-Type': 'application/json' } });
    if (url.pathname.endsWith('/token')) return response('ordinary');
    throw new Error(`Unexpected public Auth transport path: ${url.pathname}`);
  });
  vi.stubGlobal('fetch', io.fetch);
});
afterEach(async () => {
  for (const client of io.clients) await client.auth.stopAutoRefresh();
  vi.unstubAllGlobals();
});

describe('HARD-011 older real SDK operations cannot undo completed logout', () => {
  it.each(['refreshSession', 'expired-getSession', 'pkce-exchange'])('%s token response arriving after logout starts cannot restore restart session; new sign-in stays usable', async operation => {
    const native = await import('../../apps/mobile/lib/native-session');
    if (operation !== 'pkce-exchange') {
      io.bytes.set(fixture.durableKey, JSON.stringify({ ...tokenResponse('initial'), expires_at: Math.floor(Date.now() / 1000) + 3600 }));
    }
    const older = await realClient(native); const current = await realClient(native);
    if (operation === 'pkce-exchange') {
      // Public SDK OAuth entry creates its own verifier. The transport fixture never
      // invents project storage layout or bypasses the SDK PKCE protocol.
      const started = await older.auth.signInWithOAuth({ provider: 'google',
        options: { skipBrowserRedirect: true, redirectTo: 'fitcruxx://auth/callback' } });
      expect(started.error).toBeNull();
    } else if (operation === 'expired-getSession') {
      io.bytes.set(fixture.durableKey, JSON.stringify({ ...tokenResponse('expired'), expires_at: Math.floor(Date.now() / 1000) - 60 }));
    }
    const tokenGate = gate<Response>(); const requestStarted = gate<void>(); let held = false;
    const baselineFetch = io.fetch.getMockImplementation()!;
    io.fetch.mockImplementation(async (input: any, options: any) => {
      const url = new URL(typeof input === 'string' ? input : input.url);
      if (!held && url.pathname.endsWith('/token') && ['refresh_token', 'pkce'].includes(url.searchParams.get('grant_type') ?? '')) {
        held = true; requestStarted.resolve(); return tokenGate.promise;
      }
      return baselineFetch(input, options);
    });
    const oldOperation = operation === 'refreshSession' ? older.auth.refreshSession()
      : operation === 'expired-getSession' ? older.auth.getSession()
      : older.auth.exchangeCodeForSession('independent-old-auth-code');
    await requestStarted.promise;
    let logoutCompleted = false;
    const logout = native.signOutMobile(current).then(() => { logoutCompleted = true; });
    await settle();
    // Fetch/Response processing and the real SDK lock/event chains can cross a
    // macrotask boundary. Give logout bounded real event-loop opportunities to
    // finish first; a privacy-critical serialization may still keep it pending.
    for (let turn = 0; turn < 3 && !logoutCompleted; turn++) {
      await new Promise<void>(done => setTimeout(done, 0));
      await settle();
    }
    // Critical Auth work is allowed to serialize with logout. Release it before
    // awaiting completed logout, then verify the durable restart boundary.
    tokenGate.resolve(response('obsolete-operation'));
    await Promise.all([oldOperation, logout]); await settle();
    expect(io.bytes.has(fixture.durableKey)).toBe(false);
    const restarted = await realClient(native);
    const afterRestart = await restarted.auth.getSession();
    expect(afterRestart.error).toBeNull(); expect(afterRestart.data.session).toBeNull();
    const newSignIn = await restarted.auth.signInWithPassword({ email: 'sdk-only@holdout.example', password: 'synthetic-test-password' });
    expect(newSignIn.error).toBeNull(); expect(newSignIn.data.session).not.toBeNull();
    await settle();
    const usable = await restarted.auth.getSession();
    expect(usable.data.session?.user.id).toBe(fixture.userId);
    expect(io.bytes.has(fixture.durableKey)).toBe(true);
    expect(io.bytes.get(fixture.durableKey)).not.toContain('obsolete-operation');
  });
});
