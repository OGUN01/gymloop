import { describe, expect, it, vi } from 'vitest';
import { memberClassVisibilityRequestSchema, classSettingsRequestSchema } from '../classes';
import { parseMemberClassVisibilityResult } from '../classes-results';
import { readMemberClassVisibility, readMemberUpcomingClassBookings } from '../classes-data';

const id = '16300000-0000-4000-8000-000000000001';
const bookingId = '16300000-0000-4000-8000-000000000002';
const row = {
  session_id: id, service_id: id, service_name: 'Salsa beginners', service_description: null,
  branch_id: id, branch_name: 'West', timezone: 'Etc/GMT+12', session_date: '2026-10-05',
  starts_at: '2026-10-06T02:00:00Z', ends_at: '2026-10-06T03:00:00Z', trainer_name: null,
  capacity: 20, booked_count: 1, spots_left: 19, session_status: 'scheduled',
  my_booking_id: bookingId, my_booking_status: 'booked', availability: 'booked',
  can_cancel: true, cancel_by: '2026-10-06T00:00:00Z',
};
const projected = {
  sessionId: id, serviceId: id, serviceName: row.service_name, serviceDescription: null,
  branchId: id, branchName: 'West', timezone: row.timezone, sessionDate: row.session_date,
  startsAt: row.starts_at, endsAt: row.ends_at, trainerName: null,
  capacity: 20, bookedCount: 1, spotsLeft: 19, sessionStatus: 'scheduled',
  myBookingId: bookingId, myBookingStatus: 'booked', availability: 'booked',
  canCancel: true, cancelBy: row.cancel_by,
};

describe('NAVC-004 strict discovery request and result', () => {
  it.each([true, false])('accepts only the boolean discovery switch %s', (enabled) => {
    expect(memberClassVisibilityRequestSchema.parse({ enabled })).toEqual({ enabled });
  });
  it.each([null, undefined, 0, 1, 'true', 'false', {}, []].map((enabled) => [enabled]))('refuses malformed enabled %j', (enabled) => {
    expect(memberClassVisibilityRequestSchema.safeParse({ enabled }).success).toBe(false);
  });
  it.each(['tenantId', 'memberId', 'staffId', 'userId', 'member_classes_enabled', 'changed', 'extra'])('refuses caller-controlled %s', (key) => {
    expect(memberClassVisibilityRequestSchema.safeParse({ enabled: true, [key]: id }).success).toBe(false);
  });
  it('keeps ordinary class settings separate and unchanged', () => {
    expect(classSettingsRequestSchema.parse({ cancelWindowHours: 2, allowCrossBranch: false })).toEqual({ cancelWindowHours: 2, allowCrossBranch: false });
    expect(classSettingsRequestSchema.safeParse({ cancelWindowHours: 2, allowCrossBranch: false, enabled: true }).success).toBe(false);
    expect(memberClassVisibilityRequestSchema.safeParse({ enabled: true, cancelWindowHours: 2 }).success).toBe(false);
  });
  it.each([
    [{ enabled: true, changed: true }], [{ enabled: true, changed: false }],
    [{ enabled: false, changed: true }], [{ enabled: false, changed: false }],
  ].map((data) => [data]))('projects a single real boolean result %j', (data) => {
    expect(parseMemberClassVisibilityResult(data)).toEqual(data[0]);
  });
  it('returns only safe result facts', () => {
    expect(parseMemberClassVisibilityResult([{ enabled: false, changed: true, tenant_id: id, actor_user_id: id, private: 'SECRET' }])).toEqual({ enabled: false, changed: true });
  });
  it.each([
    null, undefined, [], { enabled: true, changed: true },
    [{ enabled: true, changed: true }, { enabled: false, changed: false }],
    [{ enabled: true }], [{ changed: true }], [{ enabled: null, changed: true }],
    [{ enabled: 'false', changed: true }], [{ enabled: false, changed: 0 }], [{ enabled: false, changed: null }],
  ].map((data) => [data]))('fails closed on malformed or ambiguous command result %j', (data) => {
    expect(parseMemberClassVisibilityResult(data)).toBeNull();
  });
});

describe('NAVC-004 caller-bound boolean projection', () => {
  it.each([true, false])('preserves explicit %s without exposing tenant settings', async (enabled) => {
    const rpc = vi.fn().mockResolvedValue({ data: [{ enabled, tenant_id: id, gstin: 'SECRET', pt_cancel_window_hours: 12 }], error: null });
    expect(await readMemberClassVisibility({ rpc })).toBe(enabled);
    expect(rpc.mock.calls).toEqual([['read_member_class_visibility']]);
  });
  it.each([
    null, undefined, [], { enabled: false }, [{ enabled: true }, { enabled: false }],
    [{}], [{ enabled: null }], [{ enabled: 'false' }], [{ enabled: 0 }], [{ enabled: [] }],
  ].map((data) => [data]))('does not turn unavailable or malformed projections into Off %j', async (data) => {
    const rpc = vi.fn().mockResolvedValue({ data, error: null });
    expect(await readMemberClassVisibility({ rpc })).toBeNull();
  });
  it('fails closed even when an RPC error accompanies plausible facts', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: [{ enabled: false }], error: { code: '42501', message: 'PRIVATE' } });
    expect(await readMemberClassVisibility({ rpc })).toBeNull();
  });
  it('does not share the previous caller value across clients or consume it after failure', async () => {
    const first = { rpc: vi.fn().mockResolvedValue({ data: [{ enabled: true }], error: null }) };
    const second = { rpc: vi.fn().mockResolvedValue({ data: [{ enabled: false }], error: null }) };
    expect(await readMemberClassVisibility(first)).toBe(true);
    expect(await readMemberClassVisibility(second)).toBe(false);
    first.rpc.mockResolvedValue({ data: null, error: { code: '42501' } });
    expect(await readMemberClassVisibility(first)).toBeNull();
  });
});

describe('NAVC-013/014 strict own-commitment projection', () => {
  it('uses no caller-supplied scope, preserves branch-local dates and exposes safe facts only', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: [{ ...row, member_id: id, user_id: id, trainer_staff_id: id, tenant_id: id, member_phone: 'SECRET', other_booking_id: id }], error: null });
    expect(await readMemberUpcomingClassBookings({ rpc })).toEqual([projected]);
    expect(rpc.mock.calls).toEqual([['read_member_upcoming_class_bookings']]);
  });
  it('distinguishes an authorized empty result from a failed read', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: [], error: null });
    expect(await readMemberUpcomingClassBookings({ rpc })).toEqual([]);
    rpc.mockResolvedValue({ data: [], error: { code: '42501', message: 'SECRET' } });
    expect(await readMemberUpcomingClassBookings({ rpc })).toBeNull();
  });
  it.each([
    ['cancelled_by_member', 'scheduled', 'closed'],
    ['cancelled_by_gym', 'scheduled', 'closed'],
    ['session_cancelled', 'cancelled', 'cancelled'],
  ])('preserves truthful %s commitments', async (my_booking_status, session_status, availability) => {
    const rpc = vi.fn().mockResolvedValue({ data: [{ ...row, my_booking_status, session_status, availability, can_cancel: false }], error: null });
    expect(await readMemberUpcomingClassBookings({ rpc })).toEqual([{ ...projected, myBookingStatus: my_booking_status, sessionStatus: session_status, availability, canCancel: false }]);
  });
  it.each([
    null, undefined, {}, [null], [{ ...row, my_booking_id: null }], [{ ...row, my_booking_status: null }],
    [{ ...row, my_booking_id: 'bad' }], [{ ...row, my_booking_status: 'active' }],
    [{ ...row, session_id: 'bad' }], [{ ...row, session_status: 'completed' }],
    [{ ...row, capacity: '20' }], [{ ...row, booked_count: -1 }], [{ ...row, spots_left: null }],
    [{ ...row, can_cancel: 'false' }], [{ ...row, timezone: null }], [row, { ...row, my_booking_id: null }],
  ].map((data) => [data]))('rejects malformed or unowned rows without partial/empty success %j', async (data) => {
    const rpc = vi.fn().mockResolvedValue({ data, error: null });
    expect(await readMemberUpcomingClassBookings({ rpc })).toBeNull();
  });
});
