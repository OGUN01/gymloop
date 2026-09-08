import { describe, expect, it } from 'vitest';
import { addDays, backToMember, dateField, formField } from '../shared';

/**
 * The pure half of the membership write path. Nothing here touches Supabase, so
 * it is tested directly rather than through a stub.
 *
 * `addDays` is the arithmetic behind `ends_on = starts_on + duration_days`, and
 * `dateField` is the only date validation on either membership handler — the
 * member handlers have none (see member-input.test.ts).
 */

const form = (fields: Record<string, string | File>): FormData => {
  const data = new FormData();
  for (const [key, value] of Object.entries(fields)) data.append(key, value);
  return data;
};

describe('formField', () => {
  it('collapses an absent field and a blank one to the same empty string', () => {
    expect(formField(form({}), 'reason')).toBe('');
    expect(formField(form({ reason: '' }), 'reason')).toBe('');
  });

  it('trims, so a whitespace-only reason cannot satisfy membership_pauses_reason_chk', () => {
    // The column check is `reason <> ''`, which a single space passes
    // (docs/decisions.md OPEN-011). The trim is what actually refuses it.
    expect(formField(form({ reason: '   ' }), 'reason')).toBe('');
    expect(formField(form({ reason: '  knee injury  ' }), 'reason')).toBe('knee injury');
  });

  it('treats a non-string part as absent rather than stringifying it', () => {
    const uploaded = form({ reason: new File(['x'], 'reason.txt') });
    expect(formField(uploaded, 'reason')).toBe('');
  });
});

describe('dateField', () => {
  it('accepts only YYYY-MM-DD', () => {
    expect(dateField(form({ d: '2026-09-08' }), 'd')).toBe('2026-09-08');
    expect(dateField(form({ d: '  2026-09-08  ' }), 'd')).toBe('2026-09-08');
    expect(dateField(form({ d: '2026-9-8' }), 'd')).toBeNull();
    expect(dateField(form({ d: '08/09/2026' }), 'd')).toBeNull();
    expect(dateField(form({ d: '2026-09-08T00:00:00Z' }), 'd')).toBeNull();
  });

  it('is null when the field is absent or blank', () => {
    expect(dateField(form({}), 'd')).toBeNull();
    expect(dateField(form({ d: '' }), 'd')).toBeNull();
  });

  it('rejects the shapes that parse and are still not days', () => {
    // These are the cases the regex alone lets through: Date rolls them over.
    expect(dateField(form({ d: '2026-02-31' }), 'd')).toBeNull();
    expect(dateField(form({ d: '2026-02-29' }), 'd')).toBeNull(); // 2026 is not a leap year
    expect(dateField(form({ d: '2026-13-01' }), 'd')).toBeNull();
    expect(dateField(form({ d: '2026-00-10' }), 'd')).toBeNull();
    expect(dateField(form({ d: '2026-09-00' }), 'd')).toBeNull();
    expect(dateField(form({ d: '2026-09-31' }), 'd')).toBeNull();
  });

  it('accepts a real leap day', () => {
    expect(dateField(form({ d: '2028-02-29' }), 'd')).toBe('2028-02-29');
  });
});

describe('addDays', () => {
  it('is identity for zero and steps one day at a time', () => {
    expect(addDays('2026-09-08', 0)).toBe('2026-09-08');
    expect(addDays('2026-09-08', 1)).toBe('2026-09-09');
    expect(addDays('2026-09-08', -1)).toBe('2026-09-07');
  });

  it('rolls over a month end, a short month and a year end', () => {
    expect(addDays('2026-01-31', 1)).toBe('2026-02-01');
    expect(addDays('2026-02-28', 1)).toBe('2026-03-01'); // 2026 is not a leap year
    expect(addDays('2028-02-28', 1)).toBe('2028-02-29'); // 2028 is
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addDays('2026-01-31', 30)).toBe('2026-03-02');
  });

  it('does not drift across a would-be DST boundary, because it is UTC throughout', () => {
    // A ms-arithmetic implementation in a local zone loses or gains an hour
    // here and can land on the wrong calendar day.
    expect(addDays('2026-03-07', 1)).toBe('2026-03-08');
    expect(addDays('2026-10-31', 1)).toBe('2026-11-01');
  });

  it('pins the ends_on boundary a plan sale produces', () => {
    // POST /api/memberships writes `ends_on = addDays(starts_on, duration_days)`.
    // A 30-day plan starting on the 1st therefore ends on the 31st — which is
    // 31 calendar days if `ends_on` is an inclusive last day of access, and 30
    // if it is exclusive. Nothing in openspec/specs/membership-and-money says
    // which, so this test pins the arithmetic, not the meaning.
    expect(addDays('2026-01-01', 30)).toBe('2026-01-31');
    expect(addDays('2026-01-01', 365)).toBe('2027-01-01');
  });
});

describe('backToMember', () => {
  const request = new Request('https://gym.example/api/memberships', { method: 'POST' });

  it('answers 303 so a refresh of the landing page cannot re-POST', () => {
    const response = backToMember(request, 'm-1');
    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe('https://gym.example/memberships/m-1');
  });

  it('carries a stable code, never a message, and escapes both parts', () => {
    const response = backToMember(request, 'a/b?c', 'already_live');
    const location = new URL(response.headers.get('location') ?? '');
    expect(location.pathname).toBe('/memberships/a%2Fb%3Fc');
    expect(location.searchParams.get('error')).toBe('already_live');
  });
});
