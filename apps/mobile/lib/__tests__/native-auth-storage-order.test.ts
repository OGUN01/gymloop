import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createMobileSupabase, signOutMobile } from '../native-session';

type Storage = { getItem(key: string): Promise<string | null>; setItem(key: string, value: string): Promise<void>; removeItem(key: string): Promise<void> };
const io = vi.hoisted(() => ({
  bytes: new Map<string, string>(), adapters: [] as Storage[],
  heldKey: '', release: null as null | (() => void), started: null as null | (() => void),
}));
vi.mock('expo-secure-store', () => ({
  getItemAsync: async (key: string) => io.bytes.get(key) ?? null,
  setItemAsync: async (key: string, value: string) => {
    if (key === io.heldKey) {
      io.heldKey = '';
      await new Promise<void>((done) => { io.release = () => { io.bytes.set(key, value); done(); }; io.started?.(); });
    } else io.bytes.set(key, value);
  },
  deleteItemAsync: async (key: string) => { io.bytes.delete(key); },
}));
vi.mock('expo-web-browser', () => ({ maybeCompleteAuthSession: () => undefined }));
vi.mock('../offline-check-in', async (original) => ({ ...await original<Record<string, unknown>>(), clearOfflineCheckIns: async () => undefined }));
vi.mock('@supabase/supabase-js', async (original) => ({
  ...await original<Record<string, unknown>>(),
  createClient: (_url: string, _key: string, options: { auth: { storage: Storage } }) => {
    const storage = options.auth.storage;
    io.adapters.push(storage);
    return { auth: { signOut: async () => { await storage.removeItem('sb-test-auth-token'); return { error: null }; } } };
  },
}));
const SDK_KEY = 'sb-test-auth-token';
const AUTH_KEY = `gymloop.session.${SDK_KEY}`;
const IDENTITY_KEY = 'gymloop.authenticated-identity';
const OLD = JSON.stringify({ access_token: 'old-session', refresh_token: 'old-refresh' });
const NEW = JSON.stringify({ access_token: 'new-session', refresh_token: 'new-refresh' });
function clients() {
  const config = { supabaseUrl: 'https://test.supabase.co', supabaseAnonKey: 'public-key' };
  const a = createMobileSupabase(config); const b = createMobileSupabase(config);
  return { a, b, aStorage: io.adapters[0]!, bStorage: io.adapters[1]! };
}
async function flush() { for (let i = 0; i < 24; i += 1) await Promise.resolve(); }
function hold(key: string) { io.heldKey = key; return new Promise<void>((done) => { io.started = done; }); }
beforeEach(() => { io.bytes.clear(); io.adapters = []; io.heldKey = ''; io.release = null; io.started = null; });

describe('HARD-011 device-wide authoritative Auth storage sign-out fence', () => {
  it('late pre-signout physical session write cannot survive another client sign-out or appear on restart', async () => {
    const { b, aStorage, bStorage } = clients();
    const started = hold(AUTH_KEY);
    const pending = aStorage.setItem(SDK_KEY, OLD); await started;
    const signingOut = signOutMobile(b); await flush();
    const duringSignOutRead = bStorage.getItem(SDK_KEY);
    io.release!(); await pending; await signingOut; await flush();
    expect(await duringSignOutRead).toBeNull();
    expect(io.bytes.get(AUTH_KEY) ?? null).toBeNull();
    const restarted = createMobileSupabase({ supabaseUrl: 'https://test.supabase.co', supabaseAnonKey: 'public-key' });
    expect(restarted).toBeDefined();
    expect(await io.adapters[2]!.getItem(SDK_KEY)).toBeNull();
  });

  it('retains a legitimate new session written after sign-out completes', async () => {
    const { b, aStorage, bStorage } = clients();
    const started = hold(AUTH_KEY);
    const pending = aStorage.setItem(SDK_KEY, OLD); await started;
    const signingOut = signOutMobile(b); await flush();
    io.release!(); await pending; await signingOut; await flush();
    await bStorage.setItem(SDK_KEY, NEW);
    expect(await aStorage.getItem(SDK_KEY)).toBe(NEW);
    expect(io.bytes.get(AUTH_KEY)).toBe(NEW);
  });

  it('an optional identity-cache write cannot block authoritative Auth persistence or sign-out cleanup', async () => {
    const { b, bStorage } = clients();
    const started = hold(IDENTITY_KEY);
    // Independent optional cache I/O shares the device but is not Auth storage.
    const optionalWrite = (await import('expo-secure-store')).setItemAsync(IDENTITY_KEY, 'optional-identity');
    await started;
    await bStorage.setItem(SDK_KEY, NEW);
    expect(await bStorage.getItem(SDK_KEY)).toBe(NEW);
    await signOutMobile(b);
    expect(await bStorage.getItem(SDK_KEY)).toBeNull();
    io.release!(); await optionalWrite; await flush();
    expect(await bStorage.getItem(SDK_KEY)).toBeNull();
  });
});

