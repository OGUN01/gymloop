import { describe, expect, it } from 'vitest';
import {
  calendarStreak,
  toLocalDate,
  visitStreak,
  weeklyGoalStreak,
  type StreakPause,
} from '../streaks';

/**
 * STK-001 (three rule types), STK-002 (a pause or a rest day is not a break),
 * MNY-004/005 (every date boundary is the gym's, and it is tested across
 * midnight).
 *
 * Visits are written as IST wall-clock instants (`+05:30`) so what a test
 * means is readable; the midnight-boundary cases deliberately write the same
 * moment as a `Z` instant instead, because that is where the bug lives.
 */
const IST = 'Asia/Kolkata';
const at = (day: string, wallClock = '18:00'): string => `${day}T${wallClock}:00+05:30`;
const NOW = at('2026-09-09', '09:30');

const approved = (startsOn: string, endsOn: string): StreakPause => ({
  startsOn,
  endsOn,
  approvedAt: at(startsOn, '10:00'),
  rejectedAt: null,
});

describe('toLocalDate (MNY-004)', () => {
  it('resolves an instant in the gym timezone, not in UTC', () => {
    // 19:00Z is 00:30 the next morning in Kolkata — five and a half hours of
    // every day on which UTC and the gym disagree about what day it is.
    expect(toLocalDate('2026-09-08T19:00:00Z', IST)).toBe('2026-09-09');
    expect(toLocalDate('2026-09-08T19:00:00Z', 'UTC')).toBe('2026-09-08');
  });

  it('is stable across a DST transition in a DST-observing zone (MNY-005)', () => {
    // US DST springs forward at 02:00 on 2026-03-08; 04:30Z is 23:30 on the 7th.
    expect(toLocalDate('2026-03-08T04:30:00Z', 'America/New_York')).toBe('2026-03-07');
    expect(toLocalDate('2026-03-08T18:00:00Z', 'America/New_York')).toBe('2026-03-08');
  });
});

describe('visitStreak (STK-001 visit streak)', () => {
  it('counts a 00:30 IST visit as today in the gym, and would lose a day in UTC (MNY-005)', () => {
    const visits = [at('2026-09-07'), at('2026-09-08'), '2026-09-08T19:00:00Z'];
    expect(visitStreak({ visits, asOf: NOW, timeZone: IST })).toMatchObject({
      current: 3,
      unit: 'day',
      missed: [],
    });
    // The same data in UTC folds the 9th back onto the 8th: two days, not three.
    expect(visitStreak({ visits, asOf: NOW, timeZone: 'UTC' }).current).toBe(2);
  });

  it('counts consecutive days across a DST transition (MNY-005)', () => {
    const result = visitStreak({
      visits: [
        '2026-03-07T23:00:00Z', // 18:00 EST on the 7th
        '2026-03-08T22:00:00Z', // 18:00 EDT on the 8th
        '2026-03-09T22:00:00Z',
      ],
      asOf: '2026-03-10T02:00:00Z', // 22:00 EDT on the 9th
      timeZone: 'America/New_York',
    });
    expect(result).toMatchObject({ current: 3, longest: 3, missed: [] });
  });

  it('counts several visits in one day once', () => {
    const result = visitStreak({
      visits: [at('2026-09-08', '07:00'), at('2026-09-08', '19:00')],
      asOf: NOW,
      timeZone: IST,
    });
    expect(result.current).toBe(1);
  });

  it('does not break on the day still in progress', () => {
    const visits = [at('2026-09-07'), at('2026-09-08')];
    expect(visitStreak({ visits, asOf: NOW, timeZone: IST })).toMatchObject({
      current: 2,
      missed: [],
    });
    // A day later the 9th is over and unvisited, so it is a real miss.
    expect(visitStreak({ visits, asOf: at('2026-09-10', '09:30'), timeZone: IST })).toMatchObject({
      current: 0,
      longest: 2,
      missed: ['2026-09-09'],
    });
  });

  it('reports zeros when the member has never visited', () => {
    expect(visitStreak({ visits: [], asOf: NOW, timeZone: IST })).toEqual({
      current: 0,
      longest: 0,
      unit: 'day',
      missed: [],
    });
  });

  it('STK-002: a configured rest day is not a break and is not a missed day', () => {
    const visits = [at('2026-09-05'), at('2026-09-07'), at('2026-09-08')];
    // 2026-09-06 is a Sunday.
    expect(visitStreak({ visits, asOf: NOW, timeZone: IST, restDays: [0] })).toMatchObject({
      current: 3,
      longest: 3,
      missed: [],
    });
    expect(visitStreak({ visits, asOf: NOW, timeZone: IST })).toMatchObject({
      current: 2,
      longest: 2,
      missed: ['2026-09-06'],
    });
  });

  it('STK-002: a gym holiday is not a break', () => {
    const visits = [at('2026-09-07'), at('2026-09-09', '08:00')];
    expect(
      visitStreak({ visits, asOf: NOW, timeZone: IST, holidays: ['2026-09-08'] }),
    ).toMatchObject({ current: 2, missed: [] });
  });

  it('STK-002: an approved pause bridges the streak', () => {
    const visits = [at('2026-09-01'), at('2026-09-08')];
    expect(
      visitStreak({ visits, asOf: NOW, timeZone: IST, pauses: [approved('2026-09-02', '2026-09-07')] }),
    ).toMatchObject({ current: 2, longest: 2, missed: [] });
  });

  it('STK-002: only an APPROVED pause bridges — rejected and pending do not', () => {
    const visits = [at('2026-09-01'), at('2026-09-08')];
    const rejected: StreakPause = {
      startsOn: '2026-09-02',
      endsOn: '2026-09-07',
      approvedAt: null,
      rejectedAt: at('2026-09-02', '10:00'),
    };
    const pending: StreakPause = { ...rejected, rejectedAt: null };
    for (const pause of [rejected, pending]) {
      expect(visitStreak({ visits, asOf: NOW, timeZone: IST, pauses: [pause] })).toMatchObject({
        current: 1,
        longest: 1,
        missed: ['2026-09-02', '2026-09-03', '2026-09-04', '2026-09-05', '2026-09-06', '2026-09-07'],
      });
    }
  });

  it('reports the longest run even when the current one is shorter', () => {
    const result = visitStreak({
      visits: [
        at('2026-09-01'),
        at('2026-09-02'),
        at('2026-09-03'),
        at('2026-09-04'),
        at('2026-09-08'),
      ],
      asOf: NOW,
      timeZone: IST,
    });
    expect(result).toMatchObject({ current: 1, longest: 4 });
  });
});

describe('weeklyGoalStreak (STK-001 weekly goal)', () => {
  // 2026-08-31 and 2026-09-07 are Mondays; 2026-08-30 and 2026-09-06 Sundays.
  const base = { asOf: NOW, timeZone: IST, goal: 3, weekStartDay: 1 };

  it('counts weeks, not days, and never breaks on the week in progress', () => {
    const result = weeklyGoalStreak({
      ...base,
      visits: [at('2026-08-31'), at('2026-09-02'), at('2026-09-04'), at('2026-09-07')],
    });
    // Last week met the goal; this week has one visit so far and is not a miss.
    expect(result).toEqual({ current: 1, longest: 1, unit: 'week', missed: [] });
  });

  it('counts the week in progress as soon as the goal is reached', () => {
    const result = weeklyGoalStreak({
      ...base,
      visits: [
        at('2026-08-31'),
        at('2026-09-02'),
        at('2026-09-04'),
        at('2026-09-07'),
        at('2026-09-08'),
        at('2026-09-09', '08:00'),
      ],
    });
    expect(result).toMatchObject({ current: 2, longest: 2, missed: [] });
  });

  it('reports a finished week that fell short by its start date', () => {
    const result = weeklyGoalStreak({
      ...base,
      visits: [
        at('2026-08-24'),
        at('2026-08-26'),
        at('2026-08-28'),
        at('2026-09-01'),
        at('2026-09-07'),
        at('2026-09-08'),
        at('2026-09-09', '08:00'),
      ],
    });
    expect(result).toEqual({ current: 1, longest: 1, unit: 'week', missed: ['2026-08-31'] });
  });

  it('STK-002: a week the pause made unreachable bridges instead of breaking', () => {
    const result = weeklyGoalStreak({
      ...base,
      visits: [
        at('2026-08-24'),
        at('2026-08-26'),
        at('2026-08-28'),
        at('2026-09-07'),
        at('2026-09-08'),
        at('2026-09-09', '08:00'),
      ],
      pauses: [approved('2026-08-31', '2026-09-06')],
    });
    expect(result).toMatchObject({ current: 2, longest: 2, missed: [] });
  });

  it('groups weeks by the gym week_start_day', () => {
    const visits = [at('2026-09-05'), at('2026-09-06')];
    const asOf = at('2026-09-06', '21:00');
    // Monday start: both visits are in the week in progress, so the goal is met.
    expect(weeklyGoalStreak({ ...base, visits, asOf, goal: 2 })).toMatchObject({ current: 1 });
    // Sunday start: the 6th opens a new week, leaving the finished one short.
    expect(weeklyGoalStreak({ ...base, visits, asOf, goal: 2, weekStartDay: 0 })).toMatchObject({
      current: 0,
      missed: ['2026-08-30'],
    });
  });

  it('counts days attended, not visits, so three visits in one day is one', () => {
    const result = weeklyGoalStreak({
      ...base,
      visits: [at('2026-09-07', '07:00'), at('2026-09-07', '13:00'), at('2026-09-07', '19:00')],
    });
    expect(result.current).toBe(0);
  });
});

describe('calendarStreak (STK-001 calendar streak)', () => {
  const window = { startsOn: '2026-09-01', endsOn: '2026-09-30' };

  it('ignores visits outside the challenge period', () => {
    const result = calendarStreak({
      ...window,
      visits: [at('2026-08-29'), at('2026-08-30'), at('2026-08-31'), at('2026-09-01'), at('2026-09-02')],
      asOf: at('2026-09-02', '21:00'),
      timeZone: IST,
    });
    expect(result).toEqual({ current: 2, longest: 2, unit: 'day', missed: [] });
  });

  it('does not count days the challenge has not reached as missed', () => {
    const result = calendarStreak({
      ...window,
      visits: [at('2026-09-01'), at('2026-09-03')],
      asOf: at('2026-09-03', '21:00'),
      timeZone: IST,
    });
    expect(result).toMatchObject({ current: 1, longest: 1, missed: ['2026-09-02'] });
  });

  it('STK-002: an approved pause inside the period bridges', () => {
    const result = calendarStreak({
      ...window,
      visits: [at('2026-09-01'), at('2026-09-05')],
      asOf: at('2026-09-05', '21:00'),
      timeZone: IST,
      pauses: [approved('2026-09-02', '2026-09-04')],
    });
    expect(result).toMatchObject({ current: 2, missed: [] });
  });

  it('has no streak before the challenge starts', () => {
    expect(
      calendarStreak({
        startsOn: '2026-10-01',
        endsOn: '2026-10-31',
        visits: [at('2026-09-08')],
        asOf: NOW,
        timeZone: IST,
      }),
    ).toEqual({ current: 0, longest: 0, unit: 'day', missed: [] });
  });
});
