import { describe, expect, it } from 'vitest';
import * as pt from '../pt-front';
import { formatDateTime, formatMoney } from '../../display/display';

const ids = { order: '73000000-0000-4000-8000-000000000001', session: '73000000-0000-4000-8000-000000000002', staff: '73000000-0000-4000-8000-000000000003' };
const instant = '2026-10-04T10:00:00+05:30';
const policy = { startsAt: instant, windowHours: 24, lateConsumes: true, timezone: 'Asia/Kolkata' };

describe('PTF frozen platform-free contracts', () => {
  it('PTF-009 accepts only a client id, own pack id and offset instant', () => {
    const body = { orderId: ids.order, sessionId: ids.session, startsAt: instant };
    expect(pt.ptBookRequestSchema.parse(body)).toEqual(body);
    for (const extra of [{ tenantId: ids.staff }, { trainerId: ids.staff }, { endsAt: instant }, { status: 'attended' }]) expect(pt.ptBookRequestSchema.safeParse({ ...body, ...extra }).success).toBe(false);
    for (const startsAt of ['2026-10-04T10:00:00', 'tomorrow', '']) expect(pt.ptBookRequestSchema.safeParse({ ...body, startsAt }).success).toBe(false);
  });
  it('PTF-014 cancellation, gym cancellation and waiver cannot carry hidden authority', () => {
    expect(pt.ptCancelRequestSchema.parse({ sessionId: ids.session })).toEqual({ sessionId: ids.session });
    for (const schema of [pt.ptGymCancelRequestSchema, pt.ptWaiveRequestSchema]) {
      expect(schema.parse({ sessionId: ids.session, reason: '  Desk correction  ' })).toEqual({ sessionId: ids.session, reason: 'Desk correction' });
      expect(schema.safeParse({ sessionId: ids.session, reason: 'ab' }).success).toBe(false);
      expect(schema.safeParse({ sessionId: ids.session, reason: 'Valid', tenantId: ids.staff }).success).toBe(false);
    }
  });
  it('PTF-001 own profile excludes listing and photo controls', () => {
    const own = { bio: 'Coaching', specialities: ['Strength'] };
    expect(pt.ownTrainerProfileRequestSchema.safeParse(own).success).toBe(true);
    for (const extra of [{ staffId: ids.staff }, { isListed: true }, { photoAssetId: ids.order }]) expect(pt.ownTrainerProfileRequestSchema.safeParse({ ...own, ...extra }).success).toBe(false);
    expect(pt.normalizeSpecialities([' Strength ', '', 'strength', 'Mobility'])).toEqual(['Strength', 'Mobility']);
  });
  it('PTF-007 validates calendar dates and ordered time off without accepting private identity', () => {
    const body = { staffId: ids.staff, startsOn: '2026-10-06', endsOn: '2026-10-07', reason: 'Leave' };
    expect(pt.trainerTimeOffRequestSchema.safeParse(body).success).toBe(true);
    expect(pt.trainerTimeOffRequestSchema.safeParse({ ...body, startsOn: '2026-10-08' }).success).toBe(false);
    expect(pt.trainerTimeOffRequestSchema.safeParse({ ...body, startsOn: '2026-02-30' }).success).toBe(false);
    expect(pt.trainerTimeOffRemoveRequestSchema.safeParse({ timeOffId: ids.order, tenantId: ids.staff }).success).toBe(false);
  });
  it('PTF-019 reassignment is bounded and reasoned', () => {
    const body = { fromStaffId: ids.staff, toStaffId: ids.session, reason: 'Trainer leaving' };
    expect(pt.ptReassignRequestSchema.safeParse(body).success).toBe(true);
    expect(pt.ptReassignRequestSchema.safeParse({ ...body, reason: 'ab' }).success).toBe(false);
    expect(pt.ptReassignRequestSchema.safeParse({ ...body, orderIds: ['not-an-id'] }).success).toBe(false);
    expect(pt.ptReassignRequestSchema.safeParse({ ...body, orderIds: Array.from({ length: 101 }, () => ids.order) }).success).toBe(false);
  });
  it.each([
    { cancelWindowHours: 0, lateCancelConsumes: false, sessionMinutes: 15 },
    { cancelWindowHours: 168, lateCancelConsumes: true, sessionMinutes: 180 },
  ])('PTF-020 allows policy endpoints %j', (body) => expect(pt.ptPolicyRequestSchema.safeParse(body).success).toBe(true));
  it.each([ -1, 169, 1.5 ])('PTF-020 refuses window %s', (cancelWindowHours) => expect(pt.ptPolicyRequestSchema.safeParse({ cancelWindowHours, lateCancelConsumes: true, sessionMinutes: 60 }).success).toBe(false));
  it.each([14, 181, 61])('PTF-020 refuses duration %s', (sessionMinutes) => expect(pt.ptPolicyRequestSchema.safeParse({ cancelWindowHours: 24, lateCancelConsumes: true, sessionMinutes }).success).toBe(false));
  it('PTF-006 touching windows are legal, overlapping same-day windows are not', () => {
    const a = { weekday: 1, startMinute: 360, endMinute: 420 };
    expect(pt.windowsOverlap(a, { ...a, startMinute: 420, endMinute: 480 })).toBe(false);
    expect(pt.windowsOverlap(a, { ...a, startMinute: 419, endMinute: 480 })).toBe(true);
    expect(pt.windowsOverlap(a, { ...a, weekday: 2 })).toBe(false);
    expect(pt.trainerAvailabilityRequestSchema.safeParse({ staffId: ids.staff, windows: [{ weekday: 7, startMinute: 0, endMinute: 60 }] }).success).toBe(false);
  });
  it('PTF-014 exact cutoff is free; one millisecond later uses one session', () => {
    const at = pt.ptCancellationConsequence({ ...policy, now: '2026-10-03T04:30:00.000Z' });
    expect(at).toMatchObject({ late: false, consumes: false, sentence: `Free to cancel until ${formatDateTime(at.cutoff, policy.timezone)}.` });
    expect(pt.ptBookingConsequence({ ...policy, now: '2026-10-03T04:30:00.000Z' })).toBe(`You can cancel for free until ${formatDateTime(at.cutoff, policy.timezone)}.`);
    expect(pt.ptCancellationConsequence({ ...policy, now: '2026-10-03T04:30:00.001Z' })).toMatchObject({ late: true, consumes: true, sentence: 'This is inside your cancellation window. Cancelling will use 1 session from your pack.' });
    expect(pt.ptCancellationConsequence({ ...policy, lateConsumes: false, now: '2026-10-03T04:30:00.001Z' })).toMatchObject({ late: true, consumes: false, sentence: "This is inside your cancellation window. Cancelling won't use a session from your pack." });
  });
  it('PTF-008 groups across UTC midnight in branch-local time', () => {
    const slot = { startsAt: '2026-10-03T20:00:00Z', endsAt: '2026-10-03T21:00:00Z' };
    expect(pt.groupSlotsByLocalDay([slot], 'Asia/Kolkata')).toEqual([{ date: '2026-10-04', slots: [slot] }]);
    expect(pt.formatMinuteOfDay(390)).toBe('06:30');
    expect(pt.parseMinuteOfDay('06:30')).toBe(390);
    expect(pt.parseMinuteOfDay('24:00')).toBeNull();
  });
  it.each([
    ['booked', false, 'Booked'], ['attended', false, 'Attended'], ['no_show', false, 'No-show'],
    ['cancelled_by_member', false, 'Cancelled by you'], ['cancelled_by_member', true, 'Cancelled late - session used'], ['cancelled_by_gym', false, 'Cancelled by your academy'],
  ])('PTF-012 pinned %s status', (status, consumed, label) => expect(pt.ptBookingStatusLabel(status, consumed, 'academy')).toBe(label));
  it.each([
    ['42501', null, 404, 'not_found'], ['22023', null, 400, 'invalid_request'], ['GL091', null, 409, 'already_booked'], ['GL092', 'time_off', 409, 'slot_unavailable'], ['GL093', null, 409, 'membership_not_live'], ['GL094', null, 409, 'trainer_other_branch'], ['GL095', null, 409, 'too_late_to_cancel'], ['GL096', null, 409, 'slot_taken'], ['23P01', null, 409, 'slot_taken'], ['GL097', null, 429, 'booking_rate_limited'], ['GL052', null, 409, 'idempotency_conflict'], ['GL055', 'order_unavailable', 409, 'pack_unavailable'], ['GL055', 'trainer_unavailable', 409, 'trainer_unavailable'], ['GL058', 'session_budget_exhausted', 409, 'pack_spent'], ['GL058', 'session_outside_validity', 409, 'outside_pack_dates'], ['GL058', 'invalid_session_transition', 409, 'session_closed'], ['40001', null, 409, 'retryable'], ['40P01', null, 409, 'retryable'], ['__proto__', null, 500, 'pt_failed'], ['GL055', 'invented', 500, 'pt_failed'],
  ])('PTF-027 error %s/%s is code-only', (state, detail, status, code) => expect(pt.ptApiError(state, detail)).toEqual({ status, code }));
  it('PTF-027 unknown refusal is safe and exact price never rounds through Number', () => {
    expect(pt.ptRefusalMessage('__proto__')).toBe("That isn't available.");
    expect(pt.ptRefusalMessage('slot_taken')).toBe('That time was just taken. Pick another time.');
    expect(formatMoney('9007199254740993', 'INR')).toBe('₹9,00,71,99,25,47,409.93');
  });
});
