// Independent frozen CLS contract; no implementation or peer suites were read.
import { describe, expect, it } from 'vitest';

const uuid = '74900000-0000-4000-8000-000000000001';
const shared = () => import('../../packages/shared/src/api/classes');
const records: Record<string, Record<string, unknown>> = {
  classBookRequestSchema: { sessionId: uuid },
  classBookingCancelRequestSchema: { bookingId: uuid },
  classDeskBookRequestSchema: { sessionId: uuid, memberId: uuid },
  classDeskCancelRequestSchema: { bookingId: uuid, reason: 'Desk request' },
  classAttendanceRequestSchema: { bookingId: uuid, status: 'booked' },
  serviceRequestSchema: { name: ' Yoga ', description: '   ', defaultDurationMinutes: 5, defaultCapacity: 1 },
  serviceActiveRequestSchema: { isActive: false },
  classRulesRequestSchema: { serviceId: uuid, branchId: uuid, weekdays: [0, 6], startTime: '23:59', durationMinutes: 480, capacity: 500 },
  classRuleUpdateRequestSchema: { durationMinutes: 5, capacity: 1, trainerStaffId: null, validUntil: null, isActive: false },
  classSessionRequestSchema: { serviceId: uuid, branchId: uuid, sessionDate: '2026-10-04', startTime: '00:00', durationMinutes: 5, capacity: 1 },
  classSessionUpdateRequestSchema: { sessionDate: '2026-10-04', startTime: '00:00', durationMinutes: 5, capacity: 1, trainerStaffId: null },
  classSessionCancelRequestSchema: { reason: ' Trainer unavailable ' },
  classSettingsRequestSchema: { cancelWindowHours: 0, allowCrossBranch: false },
};
type Schema = { safeParse: (value: unknown) => { success: boolean; data?: unknown } };
async function schema(name: string): Promise<Schema> {
  return (await shared() as unknown as Record<string, Schema>)[name]!;
}
describe('CLS held strict DTOs and presentation truth', () => {
  for (const [name, value] of Object.entries(records)) {
    it(`${name} accepts its frozen request`, async () => expect((await schema(name)).safeParse(value).success).toBe(true));
    for (const extra of ['tenantId', 'actedByStaffId', 'impersonationSessionId', 'overrideCapacity']) {
      it(`${name} rejects injected ${extra}`, async () => expect((await schema(name)).safeParse({ ...value, [extra]: uuid }).success).toBe(false));
    }
    it(`${name} rejects null and array bodies`, async () => {
      const target = await schema(name);
      expect(target.safeParse(null).success).toBe(false);
      expect(target.safeParse([value]).success).toBe(false);
    });
  }
  it('service trims five editable fields; activation is a separate command', async () => {
    const target = await schema('serviceRequestSchema');
    expect(target.safeParse(records.serviceRequestSchema).data).toEqual({ name: 'Yoga', description: undefined, defaultDurationMinutes: 5, defaultCapacity: 1, sortOrder: 0 });
    expect(target.safeParse({ ...records.serviceRequestSchema, isActive: true }).success).toBe(false);
  });
  for (const status of ['attended', 'no_show', 'booked']) {
    it(`accepts explicit desk marking ${status}`, async () => expect((await schema('classAttendanceRequestSchema')).safeParse({ bookingId: uuid, status }).success).toBe(true));
  }
  for (const status of ['cancelled_by_member', 'cancelled_by_gym', 'session_cancelled', 'checked_in', 'missed', '']) {
    it(`refuses inferred or cancellation mark ${status}`, async () => expect((await schema('classAttendanceRequestSchema')).safeParse({ bookingId: uuid, status }).success).toBe(false));
  }
  for (const weekdays of [[], [1, 1], [-1], [7], [1.5], [0, 1, 2, 3, 4, 5, 6, 0]]) {
    it(`rejects invalid weekly identity ${JSON.stringify(weekdays)}`, async () => expect((await schema('classRulesRequestSchema')).safeParse({ ...records.classRulesRequestSchema, weekdays }).success).toBe(false));
  }
  for (const field of ['serviceId', 'branchId', 'weekday', 'startTime']) {
    it(`rule update cannot mutate ${field}`, async () => expect((await schema('classRuleUpdateRequestSchema')).safeParse({ ...records.classRuleUpdateRequestSchema, [field]: uuid }).success).toBe(false));
  }
  for (const [name, field, values] of [
    ['serviceRequestSchema', 'defaultCapacity', [0, 501, 1.5, '1']],
    ['serviceRequestSchema', 'defaultDurationMinutes', [4, 481, 5.5]],
    ['serviceRequestSchema', 'sortOrder', [-1, 1001, 0.5]],
    ['classSettingsRequestSchema', 'cancelWindowHours', [-1, 169, 0.5, '2']],
    ['classSessionRequestSchema', 'startTime', ['24:00', '7:00', '12:60', '12:00:00']],
    ['classSessionRequestSchema', 'sessionDate', ['2026-02-30', '2026-2-01', 'invalid']],
    ['classSessionCancelRequestSchema', 'reason', ['  a ', ' '.repeat(201), 'a'.repeat(201)]],
  ] as const) {
    for (const value of values) it(`${name} rejects ${field}=${JSON.stringify(value)}`, async () => expect((await schema(name)).safeParse({ ...records[name], [field]: value }).success).toBe(false));
  }
  for (const name of ['classRulesRequestSchema', 'classSessionRequestSchema', 'classSessionUpdateRequestSchema']) {
    for (const startTime of ['00:00', '23:59']) {
      it(`${name} preserves valid wall-clock endpoint ${startTime}`, async () => {
        expect((await schema(name)).safeParse({ ...records[name], startTime }).success).toBe(true);
      });
    }
    it(`${name} rejects next-day midnight instead of changing the requested day`, async () => {
      expect((await schema(name)).safeParse({ ...records[name], startTime: '24:00' }).success).toBe(false);
    });
  }
  it('booking statuses preserve the database state machine', async () => {
    const module = await shared();
    expect(module.BOOKING_STATUSES).toEqual(['booked', 'cancelled_by_member', 'cancelled_by_gym', 'session_cancelled', 'attended', 'no_show']);
    expect(module.CLASS_SESSION_STATUSES).toEqual(['scheduled', 'cancelled']);
  });
  for (const [availability, spots, word, tone] of [
    ['open', 1, '1 spot left', 'ok'], ['open', 17, '17 spots left', 'ok'], ['booked', 0, 'Booked', 'ok'],
    ['full', 0, 'Full', 'warn'], ['closed', 17, 'Closed', 'muted'], ['cancelled', 17, 'Cancelled', 'risk'],
    ['membership_not_live', 17, 'Membership needed', 'warn'],
  ] as const) {
    it(`availability ${availability} states fact with a word`, async () => expect((await shared()).classAvailabilityLabel(availability, spots)).toEqual({ word, tone }));
  }
  it('day strip uses calendar arithmetic across leap day and year rollover', async () => {
    const { classDayStrip } = await shared();
    expect(classDayStrip('2028-02-28', 3)).toEqual(['2028-02-28', '2028-02-29', '2028-03-01']);
    expect(classDayStrip('2026-12-31', 2)).toEqual(['2026-12-31', '2027-01-01']);
  });
  const copy = {
    class_full: 'This class is full. Pick another time, or check again later in case someone cancels.',
    already_booked: "You're already booked into this class.",
    not_bookable: "This class can't be booked any more. It may have started, been cancelled or been paused.",
    membership_not_live: 'Booking needs a current membership. Ask the front desk to renew yours, then try again.',
    other_branch: 'This class is at another branch. You can book classes at your own branch.',
    cancel_window_closed: "It's too close to the start time to cancel online. Speak to the front desk if you can't make it.",
    booking_not_cancellable: "This booking can't be cancelled any more.",
    session_not_found: "That class isn't available.", booking_not_found: "That booking isn't available.",
    offline: "You're offline. Connect and try again — bookings can't be saved offline.",
    booking_failed: 'Something went wrong and nothing was changed. Try again.',
  };
  it('all eleven refusal sentences are exact', async () => expect((await shared()).CLASS_REFUSAL_COPY).toEqual(copy));
  for (const code of ['GL096', 'unknown', '__proto__', 'constructor', 'toString']) {
    it(`unrecognized ${code} gives safe fallback`, async () => expect((await shared()).classRefusalMessage(code)).toBe(copy.booking_failed));
  }
});
