import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { createMobileSupabase, signOutMobile } from '../native-session';

const disk = vi.hoisted(() => new Map<string, string>());
vi.mock('expo-secure-store', () => ({
  getItemAsync: async (key: string) => disk.get(key) ?? null,
  setItemAsync: async (key: string, value: string) => { disk.set(key, value); },
  deleteItemAsync: async (key: string) => { disk.delete(key); },
}));
vi.mock('expo-web-browser', () => ({ maybeCompleteAuthSession: () => undefined }));
vi.mock('../offline-check-in', async (original) => ({ ...await original<Record<string, unknown>>(), clearOfflineCheckIns: async () => undefined }));

const config = { supabaseUrl: 'https://sdk-race.supabase.co', supabaseAnonKey: 'public-anonymous-key' };
const USER = '11111111-1111-4111-8111-111111111111';
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>((done) => { resolve = done; }); return { promise, resolve }; }
function tokenResponse() {
  const platform = globalThis as unknown as { btoa(value: string): string };
  const encode = (value: unknown) => platform.btoa(JSON.stringify(value)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
  const now = Math.floor(Date.now() / 1000);
  const jwt = `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ sub: USER, role: 'authenticated', exp: now + 3600, iat: now })}.test-signature`;
  return { access_token: jwt, refresh_token: 'returned-refresh', expires_in: 3600, expires_at: now + 3600, token_type: 'bearer', user: {
    id: USER, aud: 'authenticated', role: 'authenticated', email: 'member@example.com',
    app_metadata: { provider: 'google', providers: ['google'] }, user_metadata: {}, created_at: '2026-01-01T00:00:00Z',
  } };
}
function response(body: unknown) {
  // Installed Auth SDK consumes Fetch Response I/O; keep its methods and auth logic real.
  const Constructor = (globalThis as unknown as { Response: new (body: string, options: { status: number; headers: Record<string, string> }) => unknown }).Response;
  return new Constructor(JSON.stringify(body), { status: 200, headers: { 'content-type': 'application/json' } });
}
async function settle() { for (let i = 0; i < 24; i += 1) await Promise.resolve(); }
async function eventLoopTurn() {
  await new Promise<void>((done) => {
    const platform = globalThis as unknown as { setTimeout(callback: () => void, delay: number): unknown };
    platform.setTimeout(done, 0);
  });
}
const clients: Array<ReturnType<typeof createMobileSupabase>> = [];
beforeEach(() => { disk.clear(); clients.length = 0; });
afterEach(() => { clients.forEach((client) => client.auth.stopAutoRefresh()); vi.unstubAllGlobals(); });

describe('HARD-011 actual Auth SDK late token response cannot undo device logout', () => {
  it('rejects stale refresh persistence after logout, including restart, while permitting a new post-logout sign-in', async () => {
    const arrival = deferred<void>(); const transport = deferred<unknown>();
    let held = false;
    vi.stubGlobal('fetch', vi.fn(async (input: unknown) => {
      const url = String(input);
      if (url.includes('/token?grant_type=refresh_token') && !held) {
        held = true; arrival.resolve(); return transport.promise;
      }
      if (url.includes('/token?grant_type=password')) return response(tokenResponse());
      if (url.includes('/logout')) return response({});
      throw new Error(`Unexpected public Auth transport: ${url}`);
    }));
    const a = createMobileSupabase(config); const b = createMobileSupabase(config); clients.push(a, b);
    await Promise.all([a.auth.getSession(), b.auth.getSession()]);
    const refreshing = a.auth.refreshSession({ refresh_token: 'earlier-refresh' });
    await arrival.promise;
    let logoutCompleted = false;
    const loggingOut = signOutMobile(b).then(() => { logoutCompleted = true; });
    // Give real Fetch/SDK promise chains macrotask turns to complete early if they
    // can. A safe implementation may instead await the held critical operation.
    for (let turn = 0; turn < 4; turn += 1) await eventLoopTurn();
    if (logoutCompleted) {
      expect([...disk.keys()].filter((key) => key.startsWith('gymloop.session.'))).toEqual([]);
    }
    // Release only after this scheduling window; never require early logout.
    transport.resolve(response(tokenResponse()));
    await refreshing; await loggingOut; await settle();
    expect([...disk.keys()].filter((key) => key.startsWith('gymloop.session.'))).toEqual([]);
    expect((await a.auth.getSession()).data.session).toBeNull();
    expect((await b.auth.getSession()).data.session).toBeNull();
    const restarted = createMobileSupabase(config); clients.push(restarted);
    expect((await restarted.auth.getSession()).data.session).toBeNull();

    const newSignIn = await restarted.auth.signInWithPassword({ email: 'member@example.com', password: 'dummy-test-password' });
    expect(newSignIn.error).toBeNull();
    expect(newSignIn.data.session?.user.id).toBe(USER);
    expect((await restarted.auth.getSession()).data.session?.user.id).toBe(USER);
    expect([...disk.keys()].some((key) => key.startsWith('gymloop.session.'))).toBe(true);
  });
});


