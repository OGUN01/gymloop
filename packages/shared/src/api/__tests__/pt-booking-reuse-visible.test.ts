import { describe, expect, it } from 'vitest';
import type { MemberTraining, PtPack, PtSession } from '../pt-front-data';

// Authored from frozen public declarations, without implementation access.
const command = {
  sessionId: '11111111-1111-4111-8111-111111111111',
  orderId: '22222222-2222-4222-8222-222222222222',
  startsAt: '2026-10-04T04:30:00.000Z',
};
const pack: PtPack = {
  orderId: command.orderId, programmeName: 'Strength', trainerKey: 'trainer',
  trainerName: 'Trainer', sessionsTotal: 10, sessionsUsed: 1,
  sessionsScheduled: 1, sessionsRemaining: 8, startsOn: '2026-10-01',
  expiresOn: '2026-11-01', state: 'live', canBook: true, timezone: 'Asia/Kolkata',
};
const session: PtSession = {
  ...command, endsAt: '2026-10-04T05:30:00.000Z', timezone: 'Asia/Kolkata',
  programmeName: 'Strength', trainerKey: 'trainer', trainerName: 'Trainer',
  status: 'cancelled_by_member', consumed: true, cancelledAt: null,
  cancelCutoff: null, lateNow: false, consumesNow: false, canCancel: false,
};
const answer = {
  ...command, endsAt: session.endsAt, status: 'booked',
  inCancelWindow: false, replayed: false,
};
function training(): MemberTraining {
  return {
    trainers: { data: [], error: null }, programmes: { data: [], error: null },
    packs: { data: [pack], error: null }, upcoming: { data: [session], error: null },
    history: { data: [], error: null },
  };
}

describe('PT booking Training projection public contract', () => {
  it('selects the exact own pack and combines complete sessions without mutation or filtering', async () => {
    const { ptBookingTrainingFacts } = await import('../pt-front-data');
    const input = training();
    const past = { ...session, orderId: 'other-order', status: 'attended' as const };
    input.history.data = [past];
    input.packs.data = [{ ...pack, orderId: 'other-order' }, pack];
    const before = structuredClone(input);
    expect(ptBookingTrainingFacts(input, command.orderId)).toEqual({
      pack, sessions: { data: [session, past], error: null },
    });
    expect(input).toEqual(before);
  });
  it.each(['failed', 'missing', 'duplicate', 'foreign'] as const)('refuses %s pack evidence', async (kind) => {
    const { ptBookingTrainingFacts } = await import('../pt-front-data');
    const input = training();
    if (kind === 'failed') input.packs.error = 'retryable';
    if (kind === 'missing') input.packs.data = null;
    if (kind === 'duplicate') input.packs.data = [pack, { ...pack }];
    if (kind === 'foreign') input.packs.data = [{ ...pack, orderId: 'foreign' }];
    expect(ptBookingTrainingFacts(input, command.orderId).pack).toBeNull();
  });
  it.each(['upcoming', 'history'] as const)('requires successful array data in %s', async (key) => {
    const { ptBookingTrainingFacts } = await import('../pt-front-data');
    const input = training();
    input[key] = { data: [session], error: 'retryable' };
    expect(ptBookingTrainingFacts(input, command.orderId).sessions).toEqual({ data: null, error: 'retryable' });
    input[key] = { data: null, error: null };
    expect(ptBookingTrainingFacts(input, command.orderId).sessions).toEqual({ data: null, error: 'retryable' });
  });
  it('keeps successful empty session sections and refuses an absent section', async () => {
    const { ptBookingTrainingFacts } = await import('../pt-front-data');
    const input = training();
    input.upcoming.data = [];
    expect(ptBookingTrainingFacts(input, command.orderId).sessions).toEqual({ data: [], error: null });
    const missing = { ...input, history: undefined } as unknown as MemberTraining;
    expect(ptBookingTrainingFacts(missing, command.orderId).sessions).toEqual({ data: null, error: 'retryable' });
  });
});

describe('PT public booking answer boundary', () => {
  it.each(['booked', 'attended', 'no_show', 'cancelled_by_member', 'cancelled_by_gym'])('decodes the actual %s replay status', async (status) => {
    const { ptBookingAnswer } = await import('../pt-front');
    const input = { ...answer, status, replayed: true };
    expect(ptBookingAnswer(input, command)).toEqual(input);
  });
  it('rejects malformed, incomplete and CLS-only answers', async () => {
    const { ptBookingAnswer } = await import('../pt-front');
    const { endsAt: omitted, ...incomplete } = answer;
    expect(omitted).toBe(session.endsAt);
    for (const input of [null, [], 'booked', incomplete, { ...answer, replayed: 'true' }, { ...answer, inCancelWindow: null }, { ...answer, status: 'session_cancelled' }]) {
      expect(ptBookingAnswer(input, command)).toBeNull();
    }
  });
  it.each(['sessionId', 'orderId', 'startsAt'] as const)('rejects changed %s retry identity', async (field) => {
    const { ptBookingAnswer } = await import('../pt-front');
    const replacement = field === 'startsAt' ? '2026-10-04T04:31:00.000Z' : '33333333-3333-4333-8333-333333333333';
    expect(ptBookingAnswer({ ...answer, [field]: replacement }, command)).toBeNull();
  });
  it('requires a recorded end strictly after the submitted start', async () => {
    const { ptBookingAnswer } = await import('../pt-front');
    for (const endsAt of ['invalid', command.startsAt, '2026-10-04T04:29:00.000Z']) {
      expect(ptBookingAnswer({ ...answer, endsAt }, command)).toBeNull();
    }
  });
});

describe('PT cancellation consumption evidence', () => {
  it.each([true, false])('returns authoritative %s without policy inference', async (consumed) => {
    const { ptBookingCancellationConsumption } = await import('../pt-front-data');
    expect(ptBookingCancellationConsumption({ data: [{ ...session, consumed }], error: null }, session)).toBe(consumed);
  });
  it('returns null for missing, failed, duplicate or nonboolean evidence', async () => {
    const { ptBookingCancellationConsumption } = await import('../pt-front-data');
    for (const section of [undefined, { data: null, error: null }, { data: [session], error: 'retryable' }, { data: [], error: null }, { data: [session, { ...session }], error: null }, { data: [{ ...session, consumed: null } as unknown as PtSession], error: null }]) {
      expect(ptBookingCancellationConsumption(section, session)).toBeNull();
    }
  });
  it('requires every exact recorded field, member cancellation, valid timezone and positive interval', async () => {
    const { ptBookingCancellationConsumption } = await import('../pt-front-data');
    const invalidRows: PtSession[] = [
      { ...session, sessionId: 'different' }, { ...session, orderId: 'different' },
      { ...session, startsAt: '2026-10-04T04:31:00.000Z' },
      { ...session, endsAt: '2026-10-04T05:31:00.000Z' },
      { ...session, status: 'cancelled_by_gym' }, { ...session, timezone: 'Invalid/Zone' },
    ];
    for (const row of invalidRows) expect(ptBookingCancellationConsumption({ data: [row], error: null }, session)).toBeNull();
    for (const row of [{ ...session, endsAt: session.startsAt }, { ...session, startsAt: 'invalid' }]) {
      expect(ptBookingCancellationConsumption({ data: [row], error: null }, row)).toBeNull();
    }
  });
});

describe('PT booking cancellation feedback reuse', () => {
  it('uses the established labels for authoritative true and false consumption', async () => {
    const { ptBookingCancellationFeedback } = await import('../pt-front-data');
    expect(ptBookingCancellationFeedback({ data: [session], error: null }, session, 'gym')).toEqual({
      message: null, label: 'Cancelled late - session used',
    });
    expect(ptBookingCancellationFeedback({ data: [{ ...session, consumed: false }], error: null }, session, 'studio')).toEqual({
      message: null, label: 'Cancelled by you',
    });
  });
  it('keeps unavailable, failed and duplicate evidence neutral', async () => {
    const { ptBookingCancellationFeedback } = await import('../pt-front-data');
    for (const section of [undefined, { data: null, error: 'retryable' }, { data: [session, { ...session }], error: null }]) {
      expect(ptBookingCancellationFeedback(section, session, 'gym')).toEqual({
        message: 'Cancelled. Reload to check whether a session was used.', label: null,
      });
    }
  });
});

describe('PT booking open-slot grouping reuse', () => {
  it('groups using each row timezone while preserving day insertion, row order and input objects', async () => {
    const { ptBookingOpenSlotGroups } = await import('../pt-front-data');
    const later = { startsAt: '2026-10-05T18:45:00.000Z', endsAt: '2026-10-05T19:45:00.000Z', timezone: 'Asia/Kolkata' };
    const earlier = { startsAt: '2026-10-04T18:45:00.000Z', endsAt: '2026-10-04T19:45:00.000Z', timezone: 'UTC' };
    const sameInstantDifferentDay = { ...earlier, timezone: 'Asia/Kolkata' };
    const sameDaySecond = { startsAt: '2026-10-04T19:00:00.000Z', endsAt: '2026-10-04T20:00:00.000Z', timezone: 'UTC' };
    const slots = { data: [later, earlier, sameInstantDifferentDay, sameDaySecond], error: null };
    const before = structuredClone({ pack, slots });
    const result = ptBookingOpenSlotGroups(pack, slots, command.orderId, Date.parse('2026-10-04T00:00:00.000Z'));
    expect([...result.entries()]).toEqual([
      ['2026-10-06', [later]], ['2026-10-04', [earlier, sameDaySecond]],
      ['2026-10-05', [sameInstantDifferentDay]],
    ]);
    expect(result.get('2026-10-06')?.[0]).toBe(later);
    expect(result.get('2026-10-04')?.[1]).toBe(sameDaySecond);
    expect({ pack, slots }).toEqual(before);
  });
  it('requires an own live explicitly bookable pack, successful array slots and finite now', async () => {
    const { ptBookingOpenSlotGroups } = await import('../pt-front-data');
    const slot = { startsAt: session.startsAt, endsAt: session.endsAt, timezone: session.timezone };
    const slots = { data: [slot], error: null };
    const now = Date.parse('2026-10-04T00:00:00.000Z');
    for (const unavailablePack of [null, undefined, { ...pack, orderId: 'foreign' }, { ...pack, state: 'closed' as const }, { ...pack, state: 'fully_booked' as const }, { ...pack, canBook: false }]) {
      expect(ptBookingOpenSlotGroups(unavailablePack, slots, command.orderId, now)).toEqual(new Map());
    }
    for (const unavailableSlots of [undefined, { data: null, error: null }, { data: [slot], error: 'retryable' }, { data: 'invalid', error: null } as unknown as typeof slots]) {
      expect(ptBookingOpenSlotGroups(pack, unavailableSlots, command.orderId, now)).toEqual(new Map());
    }
    for (const invalidNow of [NaN, Infinity, -Infinity]) {
      expect(ptBookingOpenSlotGroups(pack, slots, command.orderId, invalidNow)).toEqual(new Map());
    }
  });
  it('skips expired, exact-now and invalid interval or timezone rows without losing valid future rows', async () => {
    const { ptBookingOpenSlotGroups } = await import('../pt-front-data');
    const valid = { startsAt: session.startsAt, endsAt: session.endsAt, timezone: session.timezone };
    const now = Date.parse('2026-10-04T04:00:00.000Z');
    const slots = { data: [
      { ...valid, startsAt: '2026-10-04T03:59:00.000Z' },
      { ...valid, startsAt: '2026-10-04T04:00:00.000Z' },
      { ...valid, startsAt: 'invalid' }, { ...valid, endsAt: valid.startsAt },
      { ...valid, endsAt: '2026-10-04T04:29:00.000Z' },
      { ...valid, timezone: 'Invalid/Zone' }, valid,
    ], error: null };
    expect([...ptBookingOpenSlotGroups(pack, slots, command.orderId, now).entries()]).toEqual([
      ['2026-10-04', [valid]],
    ]);
  });
});
