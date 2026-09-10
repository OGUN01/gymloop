// Independent exact-money extension holdout, frozen contract dc391b4.
import { describe, expect, it } from 'vitest';
import { paiseFromRupees, rupeesFromPaise } from '../../../packages/shared/src/api/payments.ts';

describe('independent exact paise display contract', () => {
  it.each([
    ['0', '0.00'], ['1', '0.01'], ['9', '0.09'], ['10', '0.10'], ['99', '0.99'],
    ['100', '1.00'], ['101', '1.01'], ['105060', '1050.60'],
    ['-1', '-0.01'], ['-9', '-0.09'], ['-10', '-0.10'], ['-99', '-0.99'],
    ['-100', '-1.00'], ['-101', '-1.01'], ['-105060', '-1050.60'],
    ['9007199254740991', '90071992547409.91'],
    ['9007199254740992', '90071992547409.92'],
    ['9007199254740993', '90071992547409.93'],
    ['9223372036854775807', '92233720368547758.07'],
    ['-9223372036854775808', '-92233720368547758.08'],
    ['100000000000000000000000000000000000000000000000001',
      '1000000000000000000000000000000000000000000000000.01'],
    ['-100000000000000000000000000000000000000000000000009',
      '-1000000000000000000000000000000000000000000000000.09'],
  ])('formats canonical paise %s exactly as %s', (paise, rupees) => {
    expect(rupeesFromPaise(paise)).toBe(rupees);
  });

  it.each([
    '', ' ', ' 1', '1 ', '\n1', '1\n', '+1', '-0', '00', '01', '-01',
    '1.0', '1.01', '.01', '1e2', '0x10', '1_000', '1,000', '--1',
    'NaN', 'Infinity', '-Infinity', '１２', '१२', '1\u0000',
  ])('refuses noncanonical decimal string %j with TypeError', (value) => {
    expect(() => rupeesFromPaise(value)).toThrow(TypeError);
  });

  it.each([NaN, Infinity, -Infinity, 0.1, -0.1, 100.01, 9007199254740992, -9007199254740992])(
    'refuses unsafe or fractional number %s with RangeError', (value) => {
      expect(() => rupeesFromPaise(value)).toThrow(RangeError);
    },
  );

  it.each([
    [0, '0.00'], [1, '0.01'], [99, '0.99'], [100, '1.00'], [105060, '1050.60'],
    [-1, '-0.01'], [-101, '-1.01'],
    [9007199254740991, '90071992547409.91'], [-9007199254740991, '-90071992547409.91'],
  ])('preserves exact safe-integer number behavior for %s', (value, expected) => {
    expect(rupeesFromPaise(value)).toBe(expected);
    expect(rupeesFromPaise(String(value))).toBe(expected);
  });

  it('keeps the existing rupee-input parser contract independent of display widening', () => {
    expect(paiseFromRupees('1050.60')).toBe(105060);
    expect(paiseFromRupees('0.01')).toBe(1);
    expect(paiseFromRupees('999999999.99')).toBe(99999999999);
    for (const value of ['-1', '1.005', '1e2', '1000000000', '', '1,000.00']) {
      expect(paiseFromRupees(value)).toBeNull();
    }
  });
});
