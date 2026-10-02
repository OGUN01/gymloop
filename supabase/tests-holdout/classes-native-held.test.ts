// Frozen native public mutation contract; no new source read.
import { beforeEach, describe, expect, it, vi } from 'vitest';
const h = vi.hoisted(() => ({ online: true }));
vi.mock('expo-network', () => ({
  getNetworkStateAsync: async () => ({ isConnected: h.online, isInternetReachable: h.online }),
  useNetworkState: () => ({ isConnected: h.online, isInternetReachable: h.online }),
}));
const id = '74900000-0000-4000-8000-000000000001';
const mutations = [
  { name: 'bookClass', args: [id], route: '/api/class-bookings', body: { sessionId: id } },
  { name: 'cancelClassBooking', args: [id], route: '/api/class-bookings/cancel', body: { bookingId: id } },
  { name: 'deskBookClass', args: [id, id], route: '/api/class-bookings/desk', body: { sessionId: id, memberId: id } },
  { name: 'deskCancelClassBooking', args: [id, 'Desk request'], route: '/api/class-bookings/desk-cancel', body: { bookingId: id, reason: 'Desk request' } },
  { name: 'markClassAttendance', args: [id, 'no_show'], route: '/api/class-bookings/attendance', body: { bookingId: id, status: 'no_show' } },
];
type Mutation = (api: { post: ReturnType<typeof vi.fn> }, ...args: unknown[]) => Promise<unknown>;
async function invoke(name: string, post: ReturnType<typeof vi.fn>, args: unknown[]) {
  const module = await import('../../apps/mobile/lib/classes') as unknown as Record<string, Mutation>;
  return module[name]!({ post }, ...args);
}
beforeEach(() => { h.online = true; });
describe('CLS native mutations use existing bearer client and never queue', () => {
  for (const mutation of mutations) {
    it(`${mutation.name} forwards only frozen command fields`, async () => {
      const post = vi.fn().mockResolvedValue({ ok: true, data: { bookingId: id, status: 'booked', spotsLeft: 0 } });
      await invoke(mutation.name, post, mutation.args);
      expect(post).toHaveBeenCalledTimes(1);
      expect(post).toHaveBeenCalledWith(mutation.route, mutation.body);
    });
    it(`${mutation.name} refuses offline before dispatch and reconnect does not replay`, async () => {
      h.online = false;
      const post = vi.fn();
      const result = await invoke(mutation.name, post, mutation.args);
      expect(post).not.toHaveBeenCalled();
      expect(JSON.stringify(result)).toContain("You're offline. Connect and try again — bookings can't be saved offline.");
      h.online = true;
      await Promise.resolve();
      expect(post).not.toHaveBeenCalled();
    });
  }
});
