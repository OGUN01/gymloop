// Independent frozen PTF contract; production and peer suites remain unread.
import { describe, expect, it } from 'vitest';
const contract = () => import('../../packages/shared/src/api/pt-front');
const ids = { orderId: '73910000-0000-4000-8000-000000000001', sessionId: '73910000-0000-4000-8000-000000000002', staffId: '73910000-0000-4000-8000-000000000003' };
const booking = { orderId: ids.orderId, sessionId: ids.sessionId, startsAt: '2026-11-04T08:15:00+05:30' };
describe('independent PTF shared boundaries', () => {
  it.each([
    ['42501', null, 404, 'not_found'], ['22023', null, 400, 'invalid_request'],
    ['GL091', null, 409, 'already_booked'], ['GL092', null, 409, 'slot_unavailable'],
    ['GL093', null, 409, 'membership_not_live'], ['GL094', null, 409, 'trainer_other_branch'],
    ['GL095', null, 409, 'too_late_to_cancel'], ['GL096', null, 409, 'slot_taken'],
    ['23P01', null, 409, 'slot_taken'], ['GL097', null, 429, 'booking_rate_limited'],
    ['GL052', null, 409, 'idempotency_conflict'], ['GL055', 'order_unavailable', 409, 'pack_unavailable'],
    ['GL055', 'trainer_unavailable', 409, 'trainer_unavailable'], ['GL058', 'session_budget_exhausted', 409, 'pack_spent'],
    ['GL058', 'session_outside_validity', 409, 'outside_pack_dates'], ['GL058', 'invalid_session_transition', 409, 'session_closed'],
    ['40001', null, 409, 'retryable'], ['40P01', null, 409, 'retryable'],
    ['GL055', 'private detail', 500, 'pt_failed'], ['GL058', '__proto__', 500, 'pt_failed'],
  ])('%s/%s public refusal mapping', async (state, detail, status, code) => expect((await contract()).ptApiError(state as string, detail as string | null)).toEqual({ status, code }));
  it.each(['unknown', 'constructor', '__proto__', 'toString'])('prototype/unknown %s fails closed', async code => {
    const api = await contract(); expect(api.ptRefusalMessage(code)).toBe("That isn't available.");
    expect(api.ptApiError(code, 'private member reason')).toEqual({ status: 500, code: 'pt_failed' });
  });
  it.each([
    ['slot_taken', 'That time was just taken. Pick another time.'],
    ['slot_unavailable', "That time isn't open for booking. Pick another time."],
    ['already_booked', 'You already have a session at that time.'],
    ['membership_not_live', "Your membership isn't active on that day. Renew at the front desk to book."],
    ['trainer_other_branch', 'Your trainer works at a different branch. Ask the front desk to move your pack.'],
    ['too_late_to_cancel', "This session has already started, so it can't be cancelled here. Ask your trainer or the front desk."],
    ['pack_unavailable', "This pack can't be used for booking right now. Ask the front desk."],
    ['trainer_unavailable', "Your trainer isn't available right now. Ask the front desk to move your pack to another trainer."],
    ['pack_spent', "You've booked or used every session in this pack."],
    ['outside_pack_dates', 'That time is outside the dates your pack covers.'],
    ['booking_rate_limited', 'Too many bookings today. Try again tomorrow, or ask the front desk.'],
    ['idempotency_conflict', 'That request was already used for something else. Try again.'],
    ['retryable', 'Please try again.'], ['not_found', "That isn't available."],
  ])('%s exact truthful copy', async (code, sentence) => expect((await contract()).ptRefusalMessage(code)).toBe(sentence));
  it('offset booking keeps supplied id', async () => expect((await contract()).ptBookRequestSchema.parse(booking)).toEqual(booking));
  it.each([
    { ...booking, tenantId: ids.staffId }, { ...booking, trainerStaffId: ids.staffId }, { ...booking, endsAt: booking.startsAt },
    { ...booking, startsAt: '2026-11-04T08:15:00' }, { ...booking, orderId: '' }, { ...booking, sessionId: null },
  ])('strict booking refuses identity/duration/malformed %#', async value => expect((await contract()).ptBookRequestSchema.safeParse(value).success).toBe(false));
  it.each(['ptGymCancelRequestSchema', 'ptWaiveRequestSchema'] as const)('%s trims reason and refuses forged provenance', async name => {
    const schema = (await contract())[name];
    expect(schema.parse({ sessionId: ids.sessionId, reason: '  Restore final session  ' })).toEqual({ sessionId: ids.sessionId, reason: 'Restore final session' });
    for (const reason of ['', '  ab ', 'x'.repeat(201), null]) expect(schema.safeParse({ sessionId: ids.sessionId, reason }).success).toBe(false);
    expect(schema.safeParse({ sessionId: ids.sessionId, reason: 'Restore', completedOrder: true }).success).toBe(false);
  });
  it.each([
    { weekday: -1, startMinute: 300, endMinute: 360 }, { weekday: 7, startMinute: 300, endMinute: 360 },
    { weekday: 1, startMinute: 360, endMinute: 360 }, { weekday: 1, startMinute: 361, endMinute: 360 },
    { weekday: 1, startMinute: '300', endMinute: 360 }, { weekday: 1, start_minute: 300, end_minute: 360 },
    { weekday: 1, startMinute: 300.5, endMinute: 360 }, { weekday: 1, startMinute: 300, endMinute: 1441 },
  ])('strict availability refuses malformed window %#', async window => expect((await contract()).trainerAvailabilityRequestSchema.safeParse({ staffId: ids.staffId, windows: [window] }).success).toBe(false));
  it('empty replacement and three weekly windows are valid', async () => {
    const schema = (await contract()).trainerAvailabilityRequestSchema;
    expect(schema.safeParse({ staffId: ids.staffId, windows: [] }).success).toBe(true);
    expect(schema.safeParse({ staffId: ids.staffId, windows: [1, 3, 5].map(weekday => ({ weekday, startMinute: 330, endMinute: 480 })) }).success).toBe(true);
  });
  it.each([
    { cancelWindowHours: -1, lateCancelConsumes: true, sessionMinutes: 60 },
    { cancelWindowHours: 169, lateCancelConsumes: true, sessionMinutes: 60 },
    { cancelWindowHours: 24.5, lateCancelConsumes: true, sessionMinutes: 60 },
    { cancelWindowHours: 24, lateCancelConsumes: 'false', sessionMinutes: 60 },
    { cancelWindowHours: 24, lateCancelConsumes: false, sessionMinutes: 14 },
    { cancelWindowHours: 24, lateCancelConsumes: false, sessionMinutes: 181 },
    { cancelWindowHours: 24, lateCancelConsumes: false, sessionMinutes: 61 },
  ])('policy refuses bad bounds/coercion %#', async value => expect((await contract()).ptPolicyRequestSchema.safeParse(value).success).toBe(false));
  it('reassign admits explicit order subset without tenant authority', async () => {
    const schema = (await contract()).ptReassignRequestSchema;
    const value = { fromStaffId: ids.staffId, toStaffId: ids.sessionId, orderIds: [ids.orderId], reason: 'Trainer moved' };
    expect(schema.safeParse(value).success).toBe(true); expect(schema.safeParse({ ...value, tenantId: ids.orderId }).success).toBe(false);
  });
  it.each([
    ['2026-11-03T02:44:59.999Z', false], ['2026-11-03T02:45:00.000Z', false], ['2026-11-03T02:45:00.001Z', true],
  ])('strict cutoff at %s under both flags', async (now, late) => {
    const api = await contract();
    for (const lateConsumes of [false, true]) {
      const input = { startsAt: booking.startsAt, now, windowHours: 24, lateConsumes, timezone: 'Asia/Kolkata' };
      const cancel = api.ptCancellationConsequence(input); expect(cancel).toMatchObject({ late, consumes: late && lateConsumes });
      expect(new Date(cancel.cutoff).toISOString()).toBe('2026-11-03T02:45:00.000Z');
      if (late) expect(cancel.sentence).toBe(lateConsumes ? 'This is inside your cancellation window. Cancelling will use 1 session from your pack.' : "This is inside your cancellation window. Cancelling won't use a session from your pack.");
      else expect(cancel.sentence).toMatch(/^Free to cancel until .+\.$/);
      const book = api.ptBookingConsequence(input); expect(book.sentence).toBe(late ? cancel.sentence : cancel.sentence.replace('Free to cancel', 'You can cancel for free'));
    }
  });
  it('current policy controls preview', async () => {
    const api = await contract(); const input = { startsAt: booking.startsAt, now: '2026-11-03T14:45:00Z', windowHours: 24, lateConsumes: true, timezone: 'Asia/Kolkata' };
    expect(api.ptCancellationConsequence(input).consumes).toBe(true);
    expect(api.ptCancellationConsequence({ ...input, windowHours: 6 }).consumes).toBe(false);
    expect(api.ptCancellationConsequence({ ...input, lateConsumes: false }).consumes).toBe(false);
  });
  it.each([
    ['booked', false, 'Booked'], ['attended', false, 'Attended'], ['no_show', false, 'No-show'],
    ['cancelled_by_member', false, 'Cancelled by you'], ['cancelled_by_member', true, 'Cancelled late - session used'], ['cancelled_by_gym', false, 'Cancelled by your studio'],
  ])('%s effective consumption %s status', async (status, consumed, label) => expect((await contract()).ptBookingStatusLabel(status, consumed, 'studio')).toBe(label));
  it('slots retain exact instants while grouping by trainer local day', async () => {
    const slots = [{ startsAt: '2026-11-03T18:45:00Z', endsAt: '2026-11-03T19:45:00Z' }];
    expect((await contract()).groupSlotsByLocalDay(slots, 'Asia/Kolkata')).toEqual([{ date: '2026-11-04', slots }]);
  });
  it('half-open touching windows legal, real overlap refused, other weekdays independent', async () => {
    const api = await contract(); const window = { weekday: 2, startMinute: 360, endMinute: 480 };
    expect(api.windowsOverlap(window, { weekday: 2, startMinute: 480, endMinute: 600 })).toBe(false);
    expect(api.windowsOverlap(window, { weekday: 2, startMinute: 479, endMinute: 600 })).toBe(true);
    expect(api.windowsOverlap(window, { weekday: 3, startMinute: 360, endMinute: 480 })).toBe(false);
  });
});
