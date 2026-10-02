// Independent HARD-011 durable Auth session continuity/privacy contract.
// Actual public native factory/storage adapter and sign-out, SDK/platform I/O mocked.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const io = vi.hoisted(() => ({
  clients: [] as any[], adapters: [] as any[], bytes: new Map<string, string>(),
  read: vi.fn(), write: vi.fn(), remove: vi.fn(),
}));
vi.mock('@supabase/supabase-js', async () => ({ ...(await vi.importActual<any>('@supabase/supabase-js')),
  createClient: (_url: string, _key: string, options: any) => {
    const adapter = options.auth.storage; io.adapters.push(adapter);
    const client = { auth: { signOut: vi.fn(async () => {
      // Public Supabase Auth persistence behavior: sign-out removes its own SDK key
      // through the supplied adapter. It is not identity metadata/queue cleanup.
      await adapter.removeItem('independent-sdk-auth-token'); return { error: null };
    }) } };
    io.clients.push(client); return client;
  },
}));
vi.mock('expo-secure-store', () => ({ getItemAsync: io.read, setItemAsync: io.write, deleteItemAsync: io.remove }));
vi.mock('expo-web-browser', () => ({ maybeCompleteAuthSession: vi.fn(), openAuthSessionAsync: vi.fn() }));
vi.mock('react-native', () => ({
  Platform: { OS: 'android', select: (options: any) => options.android ?? options.default },
  AppState: { currentState: 'active', addEventListener: () => ({ remove: vi.fn() }) },
  Linking: { createURL: (path: string) => `fitcruxx://${path}` },
}));

const fixture = {
  sdkKey: 'independent-sdk-auth-token', durableKey: 'gymloop.session.independent-sdk-auth-token',
  identityKey: 'gymloop.authenticated-identity', oldBytes: 'old-private-auth-session', newBytes: 'new-private-auth-session',
};
function gate<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve };
}
async function settle() { for (let step = 0; step < 24; step++) await Promise.resolve(); }
async function factoryPair() {
  const native = await import('../../apps/mobile/lib/native-session');
  const config = { supabaseUrl: 'https://independent-durable.supabase.co', supabaseAnonKey: 'public-holdout-key' };
  const older = native.createMobileSupabase(config); const current = native.createMobileSupabase(config);
  return { native, older, current, oldStorage: io.adapters[0], currentStorage: io.adapters[1] };
}
beforeEach(() => {
  io.clients = []; io.adapters = []; io.bytes.clear();
  io.read.mockReset().mockImplementation(async (key: string) => io.bytes.get(key) ?? null);
  io.write.mockReset().mockImplementation(async (key: string, value: string) => { io.bytes.set(key, value); });
  io.remove.mockReset().mockImplementation(async (key: string) => { io.bytes.delete(key); });
});
afterEach(() => vi.unstubAllEnvs());

describe('HARD-011 device-wide durable Supabase Auth storage', () => {
  it('older physical SDK write cannot restore durable Auth bytes after another client signs out', async () => {
    const { native, current, oldStorage, currentStorage } = await factoryPair(); const physicalWrite = gate<void>();
    io.write.mockImplementation(async (key: string, value: string) => {
      if (key === fixture.durableKey && value === fixture.oldBytes) await physicalWrite.promise;
      io.bytes.set(key, value);
    });
    const olderWrite = oldStorage.setItem(fixture.sdkKey, fixture.oldBytes); await settle();
    expect(io.write).toHaveBeenCalledWith(fixture.durableKey, fixture.oldBytes);
    const logout = native.signOutMobile(current); await settle();
    expect(io.clients[1].auth.signOut).toHaveBeenCalledOnce();
    physicalWrite.resolve(); await Promise.all([olderWrite, logout]); await settle();
    expect(io.bytes.has(fixture.durableKey)).toBe(false);
    await expect(currentStorage.getItem(fixture.sdkKey)).resolves.toBeNull();
    expect(io.remove.mock.calls.some(([key]: any[]) => key !== fixture.identityKey && key !== fixture.durableKey)).toBe(true);
  });
  it('startup adapter reads wait for obsolete-write cleanup and never return the old session', async () => {
    const { native, current, oldStorage, currentStorage } = await factoryPair(); const physicalWrite = gate<void>();
    io.write.mockImplementation(async (key: string, value: string) => {
      if (key === fixture.durableKey) await physicalWrite.promise;
      io.bytes.set(key, value);
    });
    const olderWrite = oldStorage.setItem(fixture.sdkKey, fixture.oldBytes); await settle();
    const logout = native.signOutMobile(current); await settle();
    let readCompleted = false;
    const startupRead = currentStorage.getItem(fixture.sdkKey).then((value: string | null) => { readCompleted = true; return value; });
    await settle(); expect(readCompleted).toBe(false);
    physicalWrite.resolve(); await Promise.all([olderWrite, logout]);
    await expect(startupRead).resolves.toBeNull(); await settle();
    expect(io.bytes.has(fixture.durableKey)).toBe(false);
  });
  it('new legitimate post-signout sign-in persists through the same shared adapter', async () => {
    const { native, current, oldStorage, currentStorage } = await factoryPair();
    await oldStorage.setItem(fixture.sdkKey, fixture.oldBytes); await settle();
    await native.signOutMobile(current); await settle();
    await currentStorage.setItem(fixture.sdkKey, fixture.newBytes); await settle();
    await expect(currentStorage.getItem(fixture.sdkKey)).resolves.toBe(fixture.newBytes);
    expect(io.bytes.get(fixture.durableKey)).toBe(fixture.newBytes);
  });
  it.each(['failure', 'delay'])('optional identity-cache deletion %s does not block authoritative SDK Auth storage removal', async condition => {
    const { native, current, currentStorage } = await factoryPair(); const metadata = gate<void>();
    io.bytes.set(fixture.durableKey, fixture.oldBytes);
    io.remove.mockImplementation(async (key: string) => {
      if (key === fixture.identityKey) {
        if (condition === 'failure') throw new Error('Optional metadata unavailable');
        await metadata.promise;
      }
      io.bytes.delete(key);
    });
    const logout = native.signOutMobile(current); await settle();
    expect(io.clients[1].auth.signOut).toHaveBeenCalledOnce();
    // Auth persistence is a security boundary; optional metadata does not serialize
    // ahead of its removal or prevent a restart from observing the signed-out state.
    expect(io.bytes.has(fixture.durableKey)).toBe(false);
    await expect(currentStorage.getItem(fixture.sdkKey)).resolves.toBeNull();
    metadata.resolve(); await expect(logout).resolves.toBeUndefined(); await settle();
    expect(io.remove.mock.calls.some(([key]: any[]) => key !== fixture.identityKey && key !== fixture.durableKey)).toBe(true);
  });
});
