import { describe, expect, it, vi } from 'vitest';
import { bookClass, cancelClassBooking, deskBookClass, deskCancelClassBooking, markClassAttendance, loadMemberClasses, loadDeskTimetable, loadDeskRoster } from '../classes';

const id = '74000000-0000-4000-8000-000000000001';
const memberId = '74000000-0000-4000-8000-000000000002';
const window = { from: '2026-10-02', to: '2026-10-30' };
describe('CLS native bearer API contract', () => {
  it('uses only the existing API client for every explicit mutation', async () => {
    const post = vi.fn().mockResolvedValue({ ok: true, data: { bookingId: id, status: 'booked', spotsLeft: 1 } });
    const api = { post } as unknown as Parameters<typeof bookClass>[0];
    await bookClass(api, id);
    expect(post).toHaveBeenLastCalledWith('/api/class-bookings', { sessionId: id });
    await cancelClassBooking(api, id);
    expect(post).toHaveBeenLastCalledWith('/api/class-bookings/cancel', { bookingId: id });
    await deskBookClass(api, id, memberId);
    expect(post).toHaveBeenLastCalledWith('/api/class-bookings/desk', { sessionId: id, memberId });
    await deskCancelClassBooking(api, id, 'Member asked');
    expect(post).toHaveBeenLastCalledWith('/api/class-bookings/desk-cancel', { bookingId: id, reason: 'Member asked' });
    await markClassAttendance(api, id, 'attended');
    expect(post).toHaveBeenLastCalledWith('/api/class-bookings/attendance', { bookingId: id, status: 'attended' });
    expect(post).toHaveBeenCalledTimes(5);
  });
  it('does not create attendance as a side effect of booking or cancel', async () => {
    const post = vi.fn().mockResolvedValue({ ok: true, data: { bookingId: id, status: 'booked', spotsLeft: 0 } });
    const api = { post } as unknown as Parameters<typeof bookClass>[0];
    await bookClass(api, id); await cancelClassBooking(api, id);
    expect(post.mock.calls.map(([path]) => path)).toEqual(['/api/class-bookings', '/api/class-bookings/cancel']);
  });
  it('reads the safe member projection through the caller without tenant/member arguments', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: [], error: null });
    const client = { rpc } as unknown as Parameters<typeof loadMemberClasses>[0];
    await loadMemberClasses(client, window);
    expect(rpc).toHaveBeenCalledWith('read_member_class_schedule', { p_from: window.from, p_to: window.to });
    await loadDeskTimetable(client, { ...window, branchId: id });
    expect(rpc).toHaveBeenCalledWith('read_class_timetable', { p_branch_id: id, p_from: window.from, p_to: window.to });
    await loadDeskRoster(client, id);
    expect(rpc).toHaveBeenCalledWith('read_class_roster', { p_session_id: id });
  });
  it('keeps read errors distinct from empty results and retries the read explicitly', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: null, error: { message: 'PRIVATE' } });
    const client = { rpc } as unknown as Parameters<typeof loadMemberClasses>[0];
    expect(await loadMemberClasses(client, window)).toBeNull();
    expect(await loadDeskTimetable(client, { ...window, branchId: id })).toBeNull();
    expect(await loadDeskRoster(client, id)).toBeNull();
    rpc.mockResolvedValue({ data: [], error: null });
    expect(await loadMemberClasses(client, window)).toEqual([]);
    expect(rpc).toHaveBeenCalledTimes(4);
  });
});
