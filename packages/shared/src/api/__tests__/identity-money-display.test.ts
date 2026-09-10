import { describe, expect, it } from 'vitest';
import { paiseFromRupees, rupeesFromPaise } from '../payments';

// Frozen Phase 6 money addendum; authored without reading its implementation.
describe('exact money read display', () => {
  it.each([
    ['0', '0.00'], ['1', '0.01'], ['99', '0.99'], ['100', '1.00'],
    ['-1', '-0.01'], ['-99', '-0.99'], ['-101', '-1.01'],
    ['9007199254740993', '90071992547409.93'],
    ['9223372036854775807', '92233720368547758.07'],
    ['-9223372036854775808', '-92233720368547758.08'],
    ['123456789012345678901234567890123456789', '1234567890123456789012345678901234567.89'],
  ])('formats canonical %s exactly', (value, expected) => {
    expect(rupeesFromPaise(value)).toBe(expected);
  });
  it.each(['', ' ', ' 1', '1 ', '+1', '-0', '00', '01', '-01', '1.0', '1e3', 'NaN', 'Infinity', '１', '1\n'])('rejects noncanonical %j', (value) => {
    expect(() => rupeesFromPaise(value)).toThrow(TypeError);
  });
  it.each([NaN, Infinity, -Infinity, 1.5, -0.5, 9007199254740992, -9007199254740992])('refuses unsafe numeric input %s', (value) => {
    expect(() => rupeesFromPaise(value)).toThrow(RangeError);
  });
  it.each([[0, '0.00'], [1, '0.01'], [-1, '-0.01'], [150050, '1500.50'], [9007199254740991, '90071992547409.91']] as const)('preserves safe integer %s', (value, expected) => {
    expect(rupeesFromPaise(value)).toBe(expected);
  });
  it('keeps the existing rupee parser contract', () => {
    expect(paiseFromRupees('1500.50')).toBe(150050);
    expect(paiseFromRupees('0.01')).toBe(1);
  });
});
