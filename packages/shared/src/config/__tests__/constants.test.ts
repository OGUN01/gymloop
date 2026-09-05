import { describe, expect, it } from 'vitest';
import { RENEWAL_REMINDER_WINDOWS } from '../constants';

/**
 * The axis of RENEWAL_REMINDER_WINDOWS is the one thing in this file that
 * is silently catastrophic to get wrong: inverted, Phase 4 chases people
 * who have already paid and stays quiet for those about to lapse. The old
 * bare-integer form was transcribed wrongly into four documents, so the
 * semantics are pinned here rather than left to a comment.
 */
describe('RENEWAL_REMINDER_WINDOWS', () => {
  it('uses negative for before expiry and positive for after', () => {
    const byId = Object.fromEntries(RENEWAL_REMINDER_WINDOWS.map((w) => [w.id, w.daysFromExpiry]));
    expect(byId.expiry_minus_14).toBe(-14);
    expect(byId.expiry_minus_7).toBe(-7);
    expect(byId.expiry_minus_3).toBe(-3);
    expect(byId.expiry_day).toBe(0);
    // The spec writes this one as "+3", meaning three days PAST expiry.
    expect(byId.expiry_plus_3).toBe(3);
  });

  it('has exactly one post-expiry window, and it is the last one chronologically', () => {
    const after = RENEWAL_REMINDER_WINDOWS.filter((w) => w.daysFromExpiry > 0);
    expect(after).toHaveLength(1);
    const days = RENEWAL_REMINDER_WINDOWS.map((w) => w.daysFromExpiry);
    expect(days).toEqual([...days].sort((a, b) => a - b));
  });

  it('every id agrees with its own sign', () => {
    for (const { id, daysFromExpiry } of RENEWAL_REMINDER_WINDOWS) {
      if (id.includes('minus')) expect(daysFromExpiry).toBeLessThan(0);
      if (id.includes('plus')) expect(daysFromExpiry).toBeGreaterThan(0);
      if (id === 'expiry_day') expect(daysFromExpiry).toBe(0);
    }
  });
});
