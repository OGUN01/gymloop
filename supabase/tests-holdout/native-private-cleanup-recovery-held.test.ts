import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import type { ShopCacheStore } from '../../apps/mobile/lib/shop-cache';
const cleanup = vi.hoisted(() => ({ clear: vi.fn<() => Promise<void>>() }));
vi.mock('../../apps/mobile/lib/offline-check-in', () => ({ clearOfflineCheckIns: cleanup.clear }));
vi.mock('expo-secure-store', () => ({ getItemAsync: vi.fn(async () => null), setItemAsync: vi.fn(async () => undefined), deleteItemAsync: vi.fn(async () => undefined) }));
import { signOutMobile } from '../../apps/mobile/lib/native-session';
import { clearShopCache, readShopCache, writeShopCache } from '../../apps/mobile/lib/shop-cache';
function deferred() { let resolve!: () => void; const promise = new Promise<void>((done) => { resolve = done; }); return { promise, resolve }; }
const catalogue = { items: [], reservations: [], truncated: false, serverTime: '2026-10-03T10:00:00+05:30' };
beforeEach(() => { cleanup.clear.mockReset().mockResolvedValue(undefined); });
describe('independent failed private cleanup recovery', () => {
  it('retries deletion after a first Shop clear failure rather than reporting success over retained bytes', async () => {
    const values = new Map<string, string>(); let fail = true;
    const store: ShopCacheStore = { get: async (key) => values.get(key) ?? null, set: async (key, value) => { values.set(key, value); }, remove: async (key) => { if (fail) { fail = false; throw new Error('storage temporarily unavailable'); } values.delete(key); } };
    await writeShopCache(store, 'private-owner-a', catalogue); await writeShopCache(store, 'private-owner-b', catalogue);
    expect(values.size).toBeGreaterThan(0); await expect(clearShopCache(store)).rejects.toThrow(); expect(values.size).toBeGreaterThan(0);
    await clearShopCache(store); expect(values.size).toBe(0); expect(await readShopCache(store, 'private-owner-a')).toBeNull(); expect(await readShopCache(store, 'private-owner-b')).toBeNull();
    await writeShopCache(store, 'new-owner', catalogue); expect(await readShopCache(store, 'new-owner')).not.toBeNull();
  });
  it('finishes a paused recovery delete before late old Shop writes can restore private bytes', async () => {
    const values = new Map<string, string>(); const writerEntered = deferred(); const writerGate = deferred(); const deleteEntered = deferred(); const deleteGate = deferred(); let fail = true; let pauseWrite = false; let pauseDelete = false;
    const store: ShopCacheStore = { get: async (key) => values.get(key) ?? null, set: async (key, value) => { if (pauseWrite) { pauseWrite = false; writerEntered.resolve(); await writerGate.promise; } values.set(key, value); }, remove: async (key) => { if (fail) { fail = false; throw new Error('delete failed'); } if (pauseDelete) { pauseDelete = false; deleteEntered.resolve(); await deleteGate.promise; } values.delete(key); } };
    await writeShopCache(store, 'private-owner-a', catalogue); await expect(clearShopCache(store)).rejects.toThrow();
    pauseWrite = true; const oldWrite = writeShopCache(store, 'private-owner-b', catalogue); await writerEntered.promise;
    pauseDelete = true; const retry = clearShopCache(store); writerGate.resolve(); await deleteEntered.promise; deleteGate.resolve(); await Promise.all([oldWrite, retry]);
    expect(values.size).toBe(0); await writeShopCache(store, 'current-owner', catalogue); expect(await readShopCache(store, 'current-owner')).not.toBeNull();
  });
  it.each(['throw', 'reject'] as const)('attempts SDK signout while honestly rejecting %s private queue cleanup', async (mode) => {
    cleanup.clear.mockImplementation(() => { if (mode === 'throw') throw new Error('queue erase failed'); return Promise.reject(new Error('queue erase failed')); });
    const signOut = vi.fn(async () => ({ error: null })); const supabase = { auth: { signOut } } as unknown as SupabaseClient<Database>;
    await expect(signOutMobile(supabase)).rejects.toThrow(); expect(signOut).toHaveBeenCalledOnce();
  });
  it('does not report completed logout after the SDK rejects it', async () => {
    const signOut = vi.fn(async () => ({ error: new Error('SDK logout failed') })); const supabase = { auth: { signOut } } as unknown as SupabaseClient<Database>;
    await expect(signOutMobile(supabase)).rejects.toThrow(); expect(cleanup.clear).toHaveBeenCalledOnce(); expect(signOut).toHaveBeenCalledOnce();
  });
  it('completes the genuine queue cleanup and SDK logout path', async () => {
    const signOut = vi.fn(async () => ({ error: null })); const supabase = { auth: { signOut } } as unknown as SupabaseClient<Database>;
    await expect(signOutMobile(supabase)).resolves.toBeUndefined(); expect(cleanup.clear).toHaveBeenCalledOnce(); expect(signOut).toHaveBeenCalledOnce();
  });
});
