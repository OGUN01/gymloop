import { beforeEach, describe, expect, it, vi } from 'vitest';
import { signOutMobile } from '../native-session';

const io = vi.hoisted(() => ({ deleted: [] as string[], queueClears: 0 }));
vi.mock('expo-secure-store', () => ({
  getItemAsync: async () => null,
  setItemAsync: async () => undefined,
  deleteItemAsync: async (key: string) => {
    io.deleted.push(key);
    if (key === 'gymloop.authenticated-identity') throw new Error('optional identity cache unavailable');
  },
}));
vi.mock('expo-web-browser', () => ({ maybeCompleteAuthSession: () => undefined }));
vi.mock('../offline-check-in', async (original) => ({
  ...await original<Record<string, unknown>>(),
  clearOfflineCheckIns: async () => { io.queueClears += 1; },
}));

beforeEach(() => { io.deleted = []; io.queueClears = 0; });

describe('HARD-011 native authoritative sign-out survives optional identity cache failure', () => {
  it('calls auth.signOut and completes when identity-cache deletion fails after critical command cleanup', async () => {
    const signOut = vi.fn(async () => ({ error: null }));
    const supabase = { auth: { signOut } } as unknown as Parameters<typeof signOutMobile>[0];
    await expect(signOutMobile(supabase)).resolves.toBeUndefined();
    expect(io.deleted).toContain('gymloop.authenticated-identity');
    expect(io.queueClears).toBe(1);
    expect(signOut).toHaveBeenCalledTimes(1);
  });
});
