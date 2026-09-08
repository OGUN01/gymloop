import { describe, expect, it } from 'vitest';
import { paiseFromRupees, rupeesFromPaise } from '../payments';

/**
 * Written from the specification only — the implementation in ../payments
 * was not read while writing this file.
 *
 * MNY-003: more than two decimal places is REFUSED, not rounded. Postgres
 * silently rounds a `numeric` literal on its way into a `bigint` column, so
 * if this function rounded too, a receipt for an amount nobody typed would
 * reach the database with nobody the wiser.
 *
 * MNY-001: the division by 100 happens only in rupeesFromPaise. No float
 * may ever be part of paiseFromRupees's answer — `Number('1050.60') * 100`
 * is `105059.99999999999`, and several of the cases below pin the exact
 * integer for inputs where that float artifact exists, to catch a
 * reimplementation that trusts the float instead of the digits typed.
 */

describe('paiseFromRupees', () => {
  it('converts whole rupees', () => {
    expect(paiseFromRupees('1500')).toBe(150000);
    expect(paiseFromRupees('0')).toBe(0);
  });

  it('converts two decimal places directly to paise', () => {
    expect(paiseFromRupees('1500.50')).toBe(150050);
    expect(paiseFromRupees('0.01')).toBe(1);
    expect(paiseFromRupees('1500.00')).toBe(150000);
    expect(paiseFromRupees('1500.05')).toBe(150005);
  });

  it('treats one decimal digit as tenths of a rupee, not paise', () => {
    expect(paiseFromRupees('1500.5')).toBe(150050);
    expect(paiseFromRupees('0.1')).toBe(10);
  });

  it('trims leading and trailing whitespace before parsing', () => {
    expect(paiseFromRupees(' 1500 ')).toBe(150000);
    expect(paiseFromRupees('\t1500.50\n')).toBe(150050);
  });

  it('accepts up to nine digits before the point, refuses more', () => {
    expect(paiseFromRupees('999999999')).toBe(99999999900);
    expect(paiseFromRupees('1000000000')).toBeNull();
  });

  it('MNY-003: refuses three or more decimal places instead of rounding them away', () => {
    // A naive implementation might round 1500.505 to 150050 or 150051.
    // The contract is that neither happens: this input is rejected outright.
    expect(paiseFromRupees('1500.505')).toBeNull();
    expect(paiseFromRupees('0.001')).toBeNull();
  });

  it('never produces a float-contaminated result, even where Number(r) * 100 is not an integer', () => {
    // Each of these left-hand values is exact under string/decimal math, and
    // each right-hand value is what `Number(r) * 100` actually produces in
    // IEEE-754 double precision — the wrong answer a careless
    // `Math.round`/`Math.trunc`-on-a-float implementation could return.
    expect(paiseFromRupees('1050.60')).toBe(105060); // Number('1050.60') * 100 === 105059.99999999999
    expect(paiseFromRupees('19.99')).toBe(1999); // Number('19.99') * 100 === 1998.9999999999998
    expect(paiseFromRupees('0.29')).toBe(29); // Number('0.29') * 100 === 28.999999999999996
    expect(paiseFromRupees('1099.10')).toBe(109910); // Number('1099.10') * 100 === 109909.99999999999
  });

  it('rejects malformed or out-of-contract strings, returning null and never throwing or producing NaN', () => {
    const invalid = [
      '', // empty
      '-50', // negative
      '1,500', // thousands separator
      '1e3', // exponential notation
      '1500.505', // three decimal places
      '1500.', // trailing point, no digits after
      '.50', // no digits before the point
      'abc', // not a number at all
      'Infinity', // not digits
      '0x10', // hex literal
      '.', // point alone
      '1.5.0', // two decimal points
      '   ', // whitespace only, trims to empty
    ];
    for (const input of invalid) {
      const result = paiseFromRupees(input);
      expect(result, `expected null for ${JSON.stringify(input)}`).toBeNull();
      expect(Number.isNaN(result)).toBe(false);
    }
  });
});

describe('rupeesFromPaise', () => {
  it('formats paise as a rupee string with exactly two decimal places', () => {
    expect(rupeesFromPaise(150050)).toBe('1500.50');
    expect(rupeesFromPaise(150000)).toBe('1500.00');
    expect(rupeesFromPaise(1)).toBe('0.01');
    expect(rupeesFromPaise(0)).toBe('0.00');
  });

  it('always pads to two decimal digits, even for single-digit paise', () => {
    expect(rupeesFromPaise(5)).toBe('0.05');
    expect(rupeesFromPaise(9)).toBe('0.09');
    expect(rupeesFromPaise(10)).toBe('0.10');
    expect(rupeesFromPaise(100)).toBe('1.00');
  });

  it('MNY-001: keeps the correct last digit for large paise values, where division happens exactly once', () => {
    expect(rupeesFromPaise(999999999900)).toBe('9999999999.00');
    expect(rupeesFromPaise(123456789012)).toBe('1234567890.12');
    // Deliberately near Number.MAX_SAFE_INTEGER: naive `(paise / 100).toFixed(2)`
    // loses the last digit here because the float quotient is not exact,
    // even though the paise value itself is a safe integer.
    expect(rupeesFromPaise(9007199254740943)).toBe('90071992547409.43');
  });
});

describe('paiseFromRupees and rupeesFromPaise are inverses', () => {
  it('round-trips paise -> rupees -> paise across small, large, and awkward values', () => {
    // Capped at 99999999999 paise ("999999999.99"), the largest value
    // paiseFromRupees can parse back (nine digits before the point) — see
    // the reported ambiguity about rupeesFromPaise having no matching cap.
    const paiseValues = [0, 1, 9, 10, 50, 99, 100, 150000, 150050, 305, 1005, 12345678901, 99999999999];
    for (const paise of paiseValues) {
      const rupees = rupeesFromPaise(paise);
      expect(paiseFromRupees(rupees), `round-trip failed for ${paise} paise (-> "${rupees}")`).toBe(paise);
    }
  });

  it('round-trips rupees -> paise -> rupees for canonical two-decimal strings', () => {
    const rupeeStrings = ['0.00', '0.01', '0.05', '0.10', '1.00', '1500.50', '1500.00', '999999999.99'];
    for (const rupees of rupeeStrings) {
      const paise = paiseFromRupees(rupees);
      expect(paise, `expected ${rupees} to parse`).not.toBeNull();
      expect(rupeesFromPaise(paise as number), `round-trip failed for "${rupees}"`).toBe(rupees);
    }
  });
});
