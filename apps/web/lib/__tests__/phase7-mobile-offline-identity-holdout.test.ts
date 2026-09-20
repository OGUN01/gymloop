import { describe, expect, it, vi } from 'vitest';

const MEMBER_ID = '11111111-1111-4111-8111-111111111111';
const TENANT_ID = '33333333-3333-4333-8333-333333333333';
const EVENT_ID = '55555555-5555-4555-8555-555555555555';

const secureStore = new Map<string, string>();

vi.mock('expo-secure-store', () => ({
  getItemAsync: async (key: string) => secureStore.get(key) ?? null,
  setItemAsync: async (key: string, value: string) => {
    secureStore.set(key, value);
  },
  deleteItemAsync: async (key: string) => {
    secureStore.delete(key);
  },
}));

describe('Phase 7 mobile offline identity holdout', () => {
  it('GL017/GL018/GL046 retains the member queue across offline cold start and replays only after verified reconnect', async () => {
    const { drainOfflineCheckIns, loadOfflineCheckIns, saveOfflineCheckIn } =
      await import('../../../mobile/lib/offline-check-in');

    const command = {
      clientEventId: EVENT_ID,
      userId: MEMBER_ID,
      tenantId: TENANT_ID,
      memberId: MEMBER_ID,
      token: 'native-session-token',
      occurrence: '2026-09-20T08:00:00.000Z',
    };

    await saveOfflineCheckIn(command);

    // A cold start must recover the encrypted queue even when verification is unavailable.
    expect(await loadOfflineCheckIns(MEMBER_ID, TENANT_ID, MEMBER_ID)).toEqual([command]);

    const replay = vi.fn().mockRejectedValue(new Error('offline'));
    await expect(
      drainOfflineCheckIns({ userId: MEMBER_ID, tenantId: TENANT_ID, memberId: MEMBER_ID }, replay),
    ).rejects.toThrow('offline');
    expect(await loadOfflineCheckIns(MEMBER_ID, TENANT_ID, MEMBER_ID)).toEqual([command]);

    // Reconnect must use the verified server command; an offline claim cannot grant capability.
    replay.mockResolvedValue({ ok: true, verified: true });
    await drainOfflineCheckIns({ userId: MEMBER_ID, tenantId: TENANT_ID, memberId: MEMBER_ID }, replay);
    expect(replay).toHaveBeenCalledWith(command);
    expect(await loadOfflineCheckIns(MEMBER_ID, TENANT_ID, MEMBER_ID)).toEqual([]);
  });
});
