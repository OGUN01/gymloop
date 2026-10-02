import { describe, expect, it } from 'vitest';
import { Constants } from '@gymloop/db';
import * as classes from '../classes';
import { CLASS_LIMITS } from '../../config/constants';

const id = '74000000-0000-4000-8000-000000000001';
const service = { name: ' Yoga ', description: '  ', defaultDurationMinutes: 60, defaultCapacity: 20, sortOrder: 0 };
const rule = { serviceId: id, branchId: id, weekdays: [0, 6], startTime: '18:30', durationMinutes: 60, capacity: 20 };
const requests = [
  [classes.classBookRequestSchema, { sessionId: id }],
  [classes.classBookingCancelRequestSchema, { bookingId: id }],
  [classes.classDeskBookRequestSchema, { sessionId: id, memberId: id }],
  [classes.classDeskCancelRequestSchema, { bookingId: id, reason: ' Member asked ' }],
  [classes.classAttendanceRequestSchema, { bookingId: id, status: 'attended' }],
  [classes.serviceRequestSchema, service],
  [classes.serviceActiveRequestSchema, { isActive: false }],
  [classes.classRulesRequestSchema, rule],
  [classes.classRuleUpdateRequestSchema, { durationMinutes: 60, capacity: 20, trainerStaffId: null, validUntil: null, isActive: true }],
  [classes.classSessionRequestSchema, { serviceId: id, branchId: id, sessionDate: '2026-10-02', startTime: '18:30', durationMinutes: 60, capacity: 20 }],
  [classes.classSessionUpdateRequestSchema, { sessionDate: '2026-10-02', startTime: '18:30', durationMinutes: 60, capacity: 20, trainerStaffId: null }],
  [classes.classSessionCancelRequestSchema, { reason: ' Gym closed ' }],
  [classes.classSettingsRequestSchema, { cancelWindowHours: 2, allowCrossBranch: false }],
] as const;

describe('CLS shared frozen request contract', () => {
  it.each(requests)('accepts the named command and rejects caller identity fields %#', (schema, valid) => {
    expect(schema.safeParse(valid).success).toBe(true);
    for (const key of ['tenantId', 'staffId', 'userId', 'unexpected']) {
      expect(schema.safeParse({ ...valid, [key]: id }).success).toBe(false);
    }
  });
  it('pins generated status vocabularies and the complete constants parity', () => {
    expect(classes.BOOKING_STATUSES).toEqual(Constants.public.Enums.booking_status);
    expect(classes.BOOKING_STATUSES).toEqual(['booked', 'cancelled_by_member', 'cancelled_by_gym', 'session_cancelled', 'attended', 'no_show']);
    expect(classes.CLASS_SESSION_STATUSES).toEqual(Constants.public.Enums.class_session_status);
    expect(CLASS_LIMITS).toEqual({ horizonDays: 28, readWindowMaxDays: 31, nameMax: 80, descriptionMax: 500, durationMinMinutes: 5, durationMaxMinutes: 480, capacityMin: 1, capacityMax: 500, cancelWindowDefaultHours: 2, cancelWindowMaxHours: 168, markLeadMinutes: 60, markGraceHours: 24, reasonMin: 3, reasonMax: 200, maxServicesPerTenant: 50, maxActiveRulesPerTenant: 200, sortOrderMax: 1000 });
  });
  it('trims service and reason copy, with optional blank description and default sort order', () => {
    expect(classes.serviceRequestSchema.parse({ name: ' Yoga ', description: '  ', defaultDurationMinutes: 5, defaultCapacity: 1 })).toEqual({ name: 'Yoga', description: undefined, defaultDurationMinutes: 5, defaultCapacity: 1, sortOrder: 0 });
    expect(classes.classSessionCancelRequestSchema.parse({ reason: ' Gym closed ' })).toEqual({ reason: 'Gym closed' });
  });
  it.each([
    ['name', ''], ['name', ' '.repeat(80)], ['name', 'x'.repeat(81)], ['description', 'x'.repeat(501)],
    ['defaultDurationMinutes', 4], ['defaultDurationMinutes', 481], ['defaultDurationMinutes', 5.5], ['defaultDurationMinutes', '60'],
    ['defaultCapacity', 0], ['defaultCapacity', 501], ['defaultCapacity', 1.5], ['sortOrder', -1], ['sortOrder', 1001],
  ])('rejects service field %s=%j', (key, value) => {
    expect(classes.serviceRequestSchema.safeParse({ ...service, [key]: value }).success).toBe(false);
  });
  it.each([0, 168])('accepts cancellation window boundary %s', (cancelWindowHours) => {
    expect(classes.classSettingsRequestSchema.safeParse({ cancelWindowHours, allowCrossBranch: true }).success).toBe(true);
  });
  it.each([-1, 169, 1.5, '2'])('rejects cancellation window %j', (cancelWindowHours) => {
    expect(classes.classSettingsRequestSchema.safeParse({ cancelWindowHours, allowCrossBranch: false }).success).toBe(false);
  });
  it.each(['cancelled_by_member', 'cancelled_by_gym', 'session_cancelled', 'active', 'checked_in'])('never treats %s as an explicit attendance mark', (status) => {
    expect(classes.classAttendanceRequestSchema.safeParse({ bookingId: id, status }).success).toBe(false);
  });
  it.each(['attended', 'no_show', 'booked'])('accepts only an explicit %s mark', (status) => {
    expect(classes.classAttendanceRequestSchema.safeParse({ bookingId: id, status }).success).toBe(true);
  });
  it.each([[], [0, 0], [-1], [7], [1.5], ['1']].map((weekdays) => [weekdays]))('rejects weekday selection %j', (weekdays) => {
    expect(classes.classRulesRequestSchema.safeParse({ ...rule, weekdays }).success).toBe(false);
  });
  it.each(['24:00', '12:60', '9:00', '18:30:00', '18:30Z'])('rejects wall clock %s', (startTime) => {
    expect(classes.classRulesRequestSchema.safeParse({ ...rule, startTime }).success).toBe(false);
  });
  it.each(['00:00', '23:59'])('preserves valid start-day boundary %s for rules and explicit sessions', (startTime) => {
    expect(classes.classRulesRequestSchema.safeParse({ ...rule, startTime }).success).toBe(true);
    const explicit = { sessionDate: '2026-10-02', startTime, durationMinutes: 60, capacity: 20 };
    expect(classes.classSessionRequestSchema.parse({ ...explicit, serviceId: id, branchId: id })).toMatchObject(explicit);
    expect(classes.classSessionUpdateRequestSchema.parse({ ...explicit, trainerStaffId: null })).toMatchObject(explicit);
  });
  it.each(['24:00', '24:00:00', '23:60'])('rejects next-day wall time %s on explicit creation and edit', (startTime) => {
    const explicit = { sessionDate: '2026-10-02', startTime, durationMinutes: 60, capacity: 20 };
    expect(classes.classSessionRequestSchema.safeParse({ ...explicit, serviceId: id, branchId: id }).success).toBe(false);
    expect(classes.classSessionUpdateRequestSchema.safeParse({ ...explicit, trainerStaffId: null }).success).toBe(false);
  });
  it('keeps rule identity immutable and activation out of service edits', () => {
    const update = { durationMinutes: 60, capacity: 20, trainerStaffId: null, validUntil: null, isActive: true };
    for (const key of ['weekday', 'weekdays', 'startTime', 'serviceId', 'branchId', 'validFrom']) {
      expect(classes.classRuleUpdateRequestSchema.safeParse({ ...update, [key]: rule[key as keyof typeof rule] ?? id }).success).toBe(false);
    }
    expect(classes.serviceRequestSchema.safeParse({ ...service, isActive: false }).success).toBe(false);
  });
  it.each(['ab', '   ', 'x'.repeat(201)])('rejects a cancellation reason outside trimmed bounds', (reason) => {
    expect(classes.classSessionCancelRequestSchema.safeParse({ reason }).success).toBe(false);
    expect(classes.classDeskCancelRequestSchema.safeParse({ bookingId: id, reason }).success).toBe(false);
  });
  it.each(['bad', '', null])('rejects malformed booking identifiers %j', (sessionId) => {
    expect(classes.classBookRequestSchema.safeParse({ sessionId }).success).toBe(false);
  });
});

describe('CLS counts and calendar presentation', () => {
  it.each([
    ['open', 1, '1 spot left', 'ok'], ['open', 12, '12 spots left', 'ok'], ['booked', 0, 'Booked', 'ok'],
    ['full', 0, 'Full', 'warn'], ['closed', 4, 'Closed', 'muted'], ['cancelled', 20, 'Cancelled', 'risk'],
    ['membership_not_live', 20, 'Membership needed', 'warn'],
  ] as const)('labels %s without colour-only meaning', (availability, spots, word, tone) => {
    expect(classes.classAvailabilityLabel(availability, spots)).toEqual({ word, tone });
  });
  it.each([
    ['2026-12-31', ['2026-12-31', '2027-01-01', '2027-01-02']],
    ['2028-02-28', ['2028-02-28', '2028-02-29', '2028-03-01']],
    ['2026-03-07', ['2026-03-07', '2026-03-08', '2026-03-09']],
    ['2026-10-31', ['2026-10-31', '2026-11-01', '2026-11-02']],
  ])('uses local calendar dates across %s including DST transitions', (today, expected) => {
    expect(classes.classDayStrip(today, 3)).toEqual(expected);
  });
  it('can render no days without manufacturing sessions', () => expect(classes.classDayStrip('2026-10-02', 0)).toEqual([]));
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
  it('pins all exact refusal sentences and protects inherited lookup keys', () => {
    expect(classes.CLASS_REFUSAL_COPY).toEqual(copy);
    for (const [code, sentence] of Object.entries(copy)) expect(classes.classRefusalMessage(code)).toBe(sentence);
    for (const code of ['unknown', 'constructor', '__proto__', 'toString', 'GL096']) expect(classes.classRefusalMessage(code)).toBe(copy.booking_failed);
  });
});

