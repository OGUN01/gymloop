import { afterEach, describe, expect, it, vi } from 'vitest';
import type { MemberTraining, PtPack, PtSession } from '../../packages/shared/src/api/pt-front-data';

// The naive-timestamp rows below (endsAt without an offset suffix) resolve
// through Date.parse in the HOST timezone: the shared ptRecordedInterval
// accepts or rejects them depending on the runner's TZ. The expectations
// here were authored under Asia/Kolkata (a naive 09:00 lands 03:30Z, before
// the 08:00Z start, so the interval is invalid and consumption is null);
// pin the process TZ so both pinned rows behave identically on UTC runners.
process.env.TZ = 'Asia/Kolkata';

const command = {
  sessionId: '11000000-0000-4000-8000-000000000001',
  orderId: '22000000-0000-4000-8000-000000000002',
  startsAt: '2026-10-10T08:00:00.000Z',
};
const answer = {
  ...command,
  endsAt: '2026-10-10T09:00:00.000Z',
  status: 'booked',
  inCancelWindow: false,
  replayed: true,
};

afterEach(() => {
  vi.resetModules();
  vi.doUnmock('../../apps/web/lib/identity-session');
});

describe('held PT booking answer boundary', () => {
  it('returns the existing seven public fields for an exact replay', async () => {
    const { ptBookingAnswer } = await import('../../packages/shared/src/api/pt-front');
    expect(ptBookingAnswer(answer, command)).toEqual(answer);
  });

  it('accepts applicable current cancellation/completion statuses but rejects CLS status', async () => {
    const { ptBookingAnswer } = await import('../../packages/shared/src/api/pt-front');
    for (const status of ['cancelled_by_member', 'attended', 'no_show', 'cancelled_by_gym']) {
      expect(ptBookingAnswer({ ...answer, status }, command)).toEqual({ ...answer, status });
    }
    expect(ptBookingAnswer({ ...answer, status: 'session_cancelled' }, command)).toBeNull();
    expect(ptBookingAnswer({ ...answer, status: 'invented' }, command)).toBeNull();
  });

  it('requires all three exact submitted identities', async () => {
    const { ptBookingAnswer } = await import('../../packages/shared/src/api/pt-front');
    for (const changed of [
      { sessionId: '33000000-0000-4000-8000-000000000003' },
      { orderId: '33000000-0000-4000-8000-000000000003' },
      { startsAt: '2026-10-10T08:00:00+00:00' },
    ]) expect(ptBookingAnswer({ ...answer, ...changed }, command)).toBeNull();
  });

  it('rejects missing fields, wrong envelopes and invalid recorded intervals', async () => {
    const { ptBookingAnswer } = await import('../../packages/shared/src/api/pt-front');
    for (const value of [null, [answer], { data: answer },
      { ...answer, replayed: undefined }, { ...answer, inCancelWindow: 'false' },
      { ...answer, endsAt: command.startsAt }, { ...answer, endsAt: '2026-10-10T07:00:00Z' },
      { ...answer, endsAt: '2026-10-10T09:00:00' }, { ...answer, endsAt: 'not-an-instant' },
    ]) expect(ptBookingAnswer(value, command)).toBeNull();
    const malformed = { ...command, sessionId: 'not-a-uuid' };
    expect(ptBookingAnswer({ ...answer, ...malformed }, malformed)).toBeNull();
  });
});

const pack: PtPack = {
  orderId: command.orderId, programmeName: 'Strength', trainerKey: 'trainer-1',
  trainerName: 'Coach', sessionsTotal: 1, sessionsUsed: 0, sessionsScheduled: 0,
  sessionsRemaining: 1, startsOn: '2026-10-01', expiresOn: '2026-11-01',
  state: 'live', canBook: true, timezone: 'Asia/Kolkata',
};
const session: PtSession = {
  ...command, endsAt: answer.endsAt, programmeName: pack.programmeName,
  trainerKey: pack.trainerKey, trainerName: pack.trainerName, timezone: pack.timezone,
  status: 'cancelled_by_member', consumed: false, cancelledAt: null,
  cancelCutoff: null, lateNow: false, consumesNow: false, canCancel: false,
};
const training: MemberTraining = {
  trainers: { data: [], error: null }, programmes: { data: [], error: null },
  packs: { data: [pack], error: null }, upcoming: { data: [session], error: null },
  history: { data: [], error: null },
};

describe('held complete Training fact projection', () => {
  it('selects the exact pack and preserves every session and the original input', async () => {
    const { ptBookingTrainingFacts } = await import('../../packages/shared/src/api/pt-front-data');
    const other = { ...session, orderId: '33000000-0000-4000-8000-000000000003', status: 'session_cancelled' as const };
    const input = { ...training, history: { data: [other], error: null } };
    const before = structuredClone(input);
    expect(ptBookingTrainingFacts(input, command.orderId)).toEqual({
      pack, sessions: { data: [session, other], error: null },
    });
    expect(input).toEqual(before);
  });

  it('rejects missing, duplicate and failed pack facts independently of sessions', async () => {
    const { ptBookingTrainingFacts } = await import('../../packages/shared/src/api/pt-front-data');
    for (const packs of [
      { data: [], error: null }, { data: [pack, { ...pack }], error: null },
      { data: [pack], error: 'retryable' }, { data: null, error: null },
    ]) expect(ptBookingTrainingFacts({ ...training, packs }, command.orderId)).toEqual({
      pack: null, sessions: { data: [session], error: null },
    });
  });

  it('requires successful array facts from both session sections', async () => {
    const { ptBookingTrainingFacts } = await import('../../packages/shared/src/api/pt-front-data');
    for (const key of ['upcoming', 'history'] as const) {
      for (const section of [{ data: null, error: null }, { data: [session], error: 'failed' }]) {
        expect(ptBookingTrainingFacts({ ...training, [key]: section }, command.orderId)).toEqual({
          pack, sessions: { data: null, error: 'retryable' },
        });
      }
    }
    expect(ptBookingTrainingFacts({ ...training, upcoming: { data: [], error: null } }, command.orderId).sessions)
      .toEqual({ data: [], error: null });
  });
});

describe('held authoritative cancellation consumption', () => {
  it('recognizes both actual boolean values without using policy fields', async () => {
    const { ptBookingCancellationConsumption } = await import('../../packages/shared/src/api/pt-front-data');
    for (const consumed of [false, true]) {
      expect(ptBookingCancellationConsumption({ data: [{ ...session, consumed, consumesNow: !consumed }], error: null }, answer))
        .toBe(consumed);
    }
  });

  it('refuses absent, failed, duplicate and nonmatching authoritative facts', async () => {
    const { ptBookingCancellationConsumption } = await import('../../packages/shared/src/api/pt-front-data');
    for (const section of [undefined, { data: null, error: null }, { data: [], error: null },
      { data: [session], error: 'failed' }, { data: [session, { ...session }], error: null },
    ]) expect(ptBookingCancellationConsumption(section, answer)).toBeNull();
    for (const changed of [{ sessionId: pack.orderId }, { orderId: command.sessionId },
      { startsAt: '2026-10-10T08:00:00+00:00' }, { endsAt: '2026-10-10T10:00:00Z' },
    ]) expect(ptBookingCancellationConsumption({ data: [{ ...session, ...changed }], error: null }, answer)).toBeNull();
  });

  it('requires member cancellation, boolean consumption and a valid timezone/recorded interval', async () => {
    const { ptBookingCancellationConsumption } = await import('../../packages/shared/src/api/pt-front-data');
    for (const changed of [{ status: 'attended' as const }, { status: 'cancelled_by_gym' as const },
      { timezone: 'Invalid/Zone' }, { endsAt: session.startsAt }, { endsAt: '2026-10-10T09:00:00' },
    ]) {
      const row = { ...session, ...changed };
      expect(ptBookingCancellationConsumption({ data: [row], error: null }, row)).toBeNull();
    }
    const invalid = { ...session, consumed: null } as unknown as PtSession;
    expect(ptBookingCancellationConsumption({ data: [invalid], error: null }, invalid)).toBeNull();
  });
});

const original = {
  userId: '44000000-0000-4000-8000-000000000004',
  tenantId: '55000000-0000-4000-8000-000000000005',
  memberId: '66000000-0000-4000-8000-000000000006',
};

describe('held shared cancellation feedback', () => {
  it('uses exact canonical cancellation labels for authoritative false and true', async () => {
    const { ptBookingCancellationFeedback } = await import('../../packages/shared/src/api/pt-front-data');
    expect(ptBookingCancellationFeedback({ data: [session], error: null }, answer, 'studio'))
      .toEqual({ message: null, label: 'Cancelled by you' });
    expect(ptBookingCancellationFeedback({ data: [{ ...session, consumed: true }], error: null }, answer, 'studio'))
      .toEqual({ message: null, label: 'Cancelled late - session used' });
  });

  it('keeps the exact neutral acknowledgement for unavailable or ambiguous evidence', async () => {
    const { ptBookingCancellationFeedback } = await import('../../packages/shared/src/api/pt-front-data');
    for (const facts of [undefined, { data: [session], error: 'retryable' },
      { data: [session, session], error: null },
      { data: [{ ...session, timezone: 'Bad/Timezone' }], error: null },
    ]) expect(ptBookingCancellationFeedback(facts, answer, 'studio')).toEqual({
      message: 'Cancelled. Reload to check whether a session was used.', label: null,
    });
  });
});

describe('held own future row-zone slot grouping', () => {
  it('preserves row-zone day insertion, slot order, exact objects and inputs', async () => {
    const { ptBookingOpenSlotGroups } = await import('../../packages/shared/src/api/pt-front-data');
    const now = Date.parse('2026-10-10T18:00:00Z');
    const indian = { startsAt: '2026-10-10T23:30:00Z', endsAt: '2026-10-11T00:30:00Z', timezone: 'Asia/Kolkata' };
    const utc = { ...indian, timezone: 'UTC' };
    const earlierIndian = { startsAt: '2026-10-10T22:00:00Z', endsAt: '2026-10-10T23:00:00Z', timezone: 'Asia/Kolkata' };
    const slots = { data: [indian, utc, earlierIndian], error: null };
    const before = structuredClone({ pack, slots });
    const groups = ptBookingOpenSlotGroups(pack, slots, command.orderId, now);
    expect([...groups.entries()]).toEqual([
      ['2026-10-11', [indian, earlierIndian]], ['2026-10-10', [utc]],
    ]);
    expect(groups.get('2026-10-11')?.[0]).toBe(indian);
    expect(groups.get('2026-10-11')?.[1]).toBe(earlierIndian);
    expect(groups.get('2026-10-10')?.[0]).toBe(utc);
    expect({ pack, slots }).toEqual(before);
  });

  it('refuses nonfinite clocks, foreign/non-live/nonbookable packs and failed slot sections', async () => {
    const { ptBookingOpenSlotGroups } = await import('../../packages/shared/src/api/pt-front-data');
    const slots = { data: [{ startsAt: session.startsAt, endsAt: session.endsAt, timezone: session.timezone }], error: null };
    const now = Date.parse('2026-10-10T07:00:00Z');
    for (const clock of [NaN, Infinity, -Infinity]) {
      expect(ptBookingOpenSlotGroups(pack, slots, command.orderId, clock).size).toBe(0);
    }
    for (const candidate of [null, undefined, { ...pack, orderId: command.sessionId },
      { ...pack, state: 'fully_booked' as const }, { ...pack, state: 'expired' as const },
      { ...pack, state: 'closed' as const }, { ...pack, state: 'spent' as const },
      { ...pack, canBook: false }, { ...pack, canBook: undefined } as unknown as PtPack,
    ]) expect(ptBookingOpenSlotGroups(candidate, slots, command.orderId, now).size).toBe(0);
    for (const section of [undefined, { data: null, error: null }, { data: slots.data, error: 'retryable' },
      { data: {}, error: null } as unknown as typeof slots,
    ]) expect(ptBookingOpenSlotGroups(pack, section, command.orderId, now).size).toBe(0);
  });

  it('retains only valid recorded intervals strictly after the supplied instant', async () => {
    const { ptBookingOpenSlotGroups } = await import('../../packages/shared/src/api/pt-front-data');
    const now = Date.parse(session.startsAt);
    const valid = { startsAt: '2026-10-10T08:00:00.001Z', endsAt: session.endsAt, timezone: 'UTC' };
    const rows = [
      { ...valid, startsAt: session.startsAt },
      { ...valid, startsAt: '2026-10-10T07:59:59Z' },
      { ...valid, endsAt: valid.startsAt },
      { ...valid, endsAt: '2026-10-10T07:00:00Z' },
      { ...valid, endsAt: '2026-10-10T09:00:00' },
      { ...valid, startsAt: 'invalid' },
      { ...valid, timezone: 'Missing/Zone' },
      valid,
    ];
    const before = structuredClone(rows);
    expect([...ptBookingOpenSlotGroups(pack, { data: rows, error: null }, command.orderId, now)])
      .toEqual([['2026-10-10', [valid]]]);
    expect(rows).toEqual(before);
  });
});

describe('held fresh captured member guard', () => {
  it('freshly guards every invocation and returns its exact current caller/client', async () => {
    const first = { identity: { kind: 'member', ...original }, supabase: {} };
    const second = { identity: { kind: 'member', ...original }, supabase: {} };
    const guard = vi.fn().mockResolvedValueOnce(first).mockResolvedValueOnce(second);
    vi.doMock('../../apps/web/lib/identity-session', () => ({ requireAudience: guard }));
    const { requireOriginalMember } = await import('../../apps/web/lib/member-action-caller');
    expect(await requireOriginalMember(original)).toBe(first);
    expect(await requireOriginalMember(original)).toBe(second);
    expect(guard.mock.calls).toEqual([['member'], ['member']]);
  });

  it('refuses each independently changed original caller field', async () => {
    const guard = vi.fn();
    vi.doMock('../../apps/web/lib/identity-session', () => ({ requireAudience: guard }));
    const { requireOriginalMember } = await import('../../apps/web/lib/member-action-caller');
    for (const field of ['userId', 'tenantId', 'memberId'] as const) {
      guard.mockResolvedValueOnce({ identity: { kind: 'member', ...original, [field]: command.sessionId }, supabase: {} });
      expect(await requireOriginalMember(original)).toBeNull();
    }
  });

  it('sanitizes refused and throwing fresh audience reads', async () => {
    const guard = vi.fn().mockResolvedValueOnce(null).mockRejectedValueOnce(new Error('refused'));
    vi.doMock('../../apps/web/lib/identity-session', () => ({ requireAudience: guard }));
    const { requireOriginalMember } = await import('../../apps/web/lib/member-action-caller');
    expect(await requireOriginalMember(original)).toBeNull();
    expect(await requireOriginalMember(original)).toBeNull();
  });
});
