import { describe, expect, it, vi } from 'vitest';
import { loadMemberClassSchedule, loadClassTimetable, loadClassRoster } from '../classes';

const id = '74000000-0000-4000-8000-000000000001';
const window = { from: '2026-10-02', to: '2026-10-30' };
const row = {
  session_id: id, service_id: id, service_name: 'Yoga', service_description: null, branch_id: id, branch_name: 'Main', timezone: 'Asia/Kolkata',
  session_date: '2026-10-02', starts_at: '2026-10-02T12:30:00Z', ends_at: '2026-10-02T13:30:00Z', trainer_name: 'Teacher', capacity: 20,
  booked_count: 11, spots_left: 9, session_status: 'scheduled', my_booking_id: null, my_booking_status: null, availability: 'open', can_cancel: false, cancel_by: null,
};
describe('CLS caller-scoped read adapters', () => {
  it('maps member safe facts and never exposes unexpected other-member or trainer identifiers', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: [{ ...row, member_phone: 'SECRET', trainer_staff_id: id, tenant_id: id, other_booking_id: id }], error: null });
    const client = { rpc } as unknown as Parameters<typeof loadMemberClassSchedule>[0];
    const result = await loadMemberClassSchedule(client, window);
    expect(rpc).toHaveBeenCalledWith('read_member_class_schedule', { p_from: window.from, p_to: window.to });
    expect(result).toEqual([{
      sessionId: id, serviceId: id, serviceName: 'Yoga', serviceDescription: null, branchId: id, branchName: 'Main', timezone: 'Asia/Kolkata',
      sessionDate: row.session_date, startsAt: row.starts_at, endsAt: row.ends_at, trainerName: 'Teacher', capacity: 20, bookedCount: 11, spotsLeft: 9,
      sessionStatus: 'scheduled', myBookingId: null, myBookingStatus: null, availability: 'open', canCancel: false, cancelBy: null,
    }]);
  });
  it('distinguishes empty schedules from unavailable reads', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: [], error: null });
    const client = { rpc } as unknown as Parameters<typeof loadMemberClassSchedule>[0];
    expect(await loadMemberClassSchedule(client, window)).toEqual([]);
    rpc.mockResolvedValue({ data: null, error: { message: 'PRIVATE' } });
    expect(await loadMemberClassSchedule(client, window)).toBeNull();
  });
  it('uses invoker staff timetable and roster with no supplied tenant scope', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: [], error: null });
    const client = { rpc } as unknown as Parameters<typeof loadClassTimetable>[0];
    expect(await loadClassTimetable(client, { ...window, branchId: id })).toEqual([]);
    expect(rpc).toHaveBeenCalledWith('read_class_timetable', { p_branch_id: id, p_from: window.from, p_to: window.to });
    expect(await loadClassRoster(client, id)).toEqual([]);
    expect(rpc).toHaveBeenCalledWith('read_class_roster', { p_session_id: id });
  });
  it('never turns failed staff reads into an empty success', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: [], error: { message: 'PRIVATE' } });
    const client = { rpc } as unknown as Parameters<typeof loadClassTimetable>[0];
    expect(await loadClassTimetable(client, { ...window, branchId: id })).toBeNull();
    expect(await loadClassRoster(client, id)).toBeNull();
  });
});
