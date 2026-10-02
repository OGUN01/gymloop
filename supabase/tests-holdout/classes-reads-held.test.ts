// Independent frozen public loaders; the client supplied is the authority.
import { describe, expect, it, vi } from 'vitest';
const id = '74900000-0000-4000-8000-000000000001';
const other = '74900000-0000-4000-8000-000000000002';
const window = { from: '2026-10-04', to: '2026-10-05' };
const row = {
  session_id: id, service_id: id, service_name: 'Yoga', service_description: null,
  branch_id: id, branch_name: 'East', timezone: 'Pacific/Kiritimati', session_date: '2026-10-04',
  starts_at: '2026-10-03T10:30:00Z', ends_at: '2026-10-03T11:15:00Z', trainer_name: 'Teacher',
  capacity: 1, booked_count: 1, spots_left: 0, session_status: 'scheduled',
  my_booking_id: id, my_booking_status: 'booked', availability: 'booked', can_cancel: true,
  cancel_by: '2026-10-03T08:30:00Z',
};
type Loader = (client: unknown, options: unknown) => Promise<unknown>;
const platforms = [
  { name: 'web', path: '../../apps/web/lib/classes', member: 'loadMemberClassSchedule', timetable: 'loadClassTimetable', roster: 'loadClassRoster' },
  { name: 'native', path: '../../apps/mobile/lib/classes', member: 'loadMemberClasses', timetable: 'loadDeskTimetable', roster: 'loadDeskRoster' },
];
async function load(platform: typeof platforms[number], name: string, client: unknown, options: unknown) {
  const module = (platform.name === 'web'
    ? await import('../../apps/web/lib/classes')
    : await import('../../apps/mobile/lib/classes')) as unknown as Record<string, Loader>;
  return module[name]!(client, options);
}
describe('CLS public read adapters preserve caller, timezone and own booking truth', () => {
  for (const platform of platforms) {
    it(`${platform.name} member read dispatches only inclusive dates, no invented tenant/member`, async () => {
      const rpc = vi.fn().mockResolvedValue({ data: [row], error: null });
      const result = await load(platform, platform.member, { rpc }, window);
      expect(rpc).toHaveBeenCalledTimes(1);
      expect(rpc).toHaveBeenCalledWith('read_member_class_schedule', { p_from: window.from, p_to: window.to });
      expect(result).toEqual([expect.objectContaining({ sessionId: id, timezone: 'Pacific/Kiritimati', sessionDate: '2026-10-04', spotsLeft: 0, myBookingStatus: 'booked', canCancel: true, cancelBy: row.cancel_by })]);
    });
    it(`${platform.name} empty schedule is an empty result`, async () => {
      expect(await load(platform, platform.member, { rpc: vi.fn().mockResolvedValue({ data: [], error: null }) }, window)).toEqual([]);
    });
    it(`${platform.name} member projection excludes unexpected other-member and trainer-private fields`, async () => {
      const rpc = vi.fn().mockResolvedValue({ data: [{ ...row, member_id: other, member_name: 'Held Other Person', member_phone: '+919000007490', trainer_staff_id: other, trainer_email: 'held-private@example.invalid' }], error: null });
      const result = JSON.stringify(await load(platform, platform.member, { rpc }, window));
      for (const secret of [other, 'Held Other Person', '+919000007490', 'held-private@example.invalid']) expect(result).not.toContain(secret);
    });
    it(`${platform.name} never infers attendance from a past booked row`, async () => {
      const rpc = vi.fn().mockResolvedValue({ data: [{ ...row, starts_at: '2020-01-01T00:00:00Z', ends_at: '2020-01-01T01:00:00Z', can_cancel: false }], error: null });
      const result = await load(platform, platform.member, { rpc }, window);
      expect(result).toEqual([expect.objectContaining({ myBookingStatus: 'booked' })]);
      expect(rpc).toHaveBeenCalledTimes(1);
    });
    it(`${platform.name} reads each supplied identity client independently`, async () => {
      const first = { rpc: vi.fn().mockResolvedValue({ data: [row], error: null }) };
      const second = { rpc: vi.fn().mockResolvedValue({ data: [{ ...row, session_id: other, my_booking_id: null, my_booking_status: null, availability: 'full', can_cancel: false, cancel_by: null }], error: null }) };
      await load(platform, platform.member, first, window);
      const result = await load(platform, platform.member, second, window);
      expect(second.rpc).toHaveBeenCalledTimes(1);
      expect(result).toEqual([expect.objectContaining({ sessionId: other, myBookingId: null, myBookingStatus: null, canCancel: false, cancelBy: null })]);
    });
    it(`${platform.name} timetable sends the branch filter through caller RPC`, async () => {
      const rpc = vi.fn().mockResolvedValue({ data: [], error: null });
      await load(platform, platform.timetable, { rpc }, { branchId: id, ...window });
      expect(rpc).toHaveBeenCalledWith('read_class_timetable', { p_branch_id: id, p_from: window.from, p_to: window.to });
    });
    it(`${platform.name} roster sends only session id through caller RPC`, async () => {
      const rpc = vi.fn().mockResolvedValue({ data: [], error: null });
      await load(platform, platform.roster, { rpc }, id);
      expect(rpc).toHaveBeenCalledWith('read_class_roster', { p_session_id: id });
    });
  }
  it('web read error fails closed with null', async () => {
    expect(await load(platforms[0]!, platforms[0]!.member, { rpc: vi.fn().mockResolvedValue({ data: [row], error: { code: '42501' } }) }, window)).toBeNull();
  });
});
