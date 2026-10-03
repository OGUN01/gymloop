import { beforeEach, describe, expect, it, vi } from 'vitest';
import { signOutMobile } from '../native-session';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';

const cleanup = vi.hoisted(() => ({ clear: vi.fn() }));
vi.mock('../offline-check-in', () => ({ clearOfflineCheckIns: cleanup.clear }));
vi.mock('expo-secure-store', () => ({ getItemAsync: vi.fn(async () => null), setItemAsync: vi.fn(async () => undefined), deleteItemAsync: vi.fn(async () => undefined) }));
function caller(signOut: () => Promise<{ error: null | Error }>): SupabaseClient<Database> {
  return { auth: { signOut } } as SupabaseClient<Database>;
}
describe('native completed logout and failed private cleanup', () => {
  beforeEach(() => { cleanup.clear.mockReset().mockResolvedValue(undefined); });
  it('still attempts SDK logout once when offline queue cleanup fails and reports failure', async () => {
    cleanup.clear.mockRejectedValue(new Error('Private queue cleanup failed'));
    const signOut = vi.fn(async () => ({ error: null }));
    await expect(signOutMobile(caller(signOut))).rejects.toThrow();
    expect(signOut).toHaveBeenCalledTimes(1);
  });
  it('does not report completion when both queue cleanup and SDK logout fail', async () => {
    cleanup.clear.mockRejectedValue(new Error('Private queue cleanup failed'));
    const signOut = vi.fn(async () => ({ error: new Error('SDK logout failed') }));
    await expect(signOutMobile(caller(signOut))).rejects.toThrow();
    expect(signOut).toHaveBeenCalledTimes(1);
  });
  it('reports completed logout after successful private cleanup and SDK logout', async () => {
    const signOut = vi.fn(async () => ({ error: null }));
    await expect(signOutMobile(caller(signOut))).resolves.toBeUndefined();
    expect(cleanup.clear).toHaveBeenCalledTimes(1);
    expect(signOut).toHaveBeenCalledTimes(1);
  });
});
