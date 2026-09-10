import { describe, expect, it } from 'vitest';
import { membershipNetPrice } from '../membership-price';

// Written from membership-net-price/spec.md, without reading implementation.
// Expected answers are literals: the test does not repeat the subtraction.
describe('membershipNetPrice', () => {
  it.each([
    { price: 1200000, discount: 120000, expected: 1080000 },
    { price: 100005, discount: 19999, expected: 80006 },
    { price: 1, discount: 0, expected: 1 },
    { price: 1, discount: 1, expected: 0 },
    { price: 0, discount: 0, expected: 0 },
    { price: 1200000, discount: 1200000, expected: 0 },
    { price: 9007199254740991, discount: 0, expected: 9007199254740991 },
    { price: 9007199254740991, discount: 9007199254740990, expected: 1 },
    { price: 9007199254740991, discount: 9007199254740991, expected: 0 },
  ])('returns exactly $expected paise for $price less $discount', ({ price, discount, expected }) => {
    expect(membershipNetPrice(price, discount)).toBe(expected);
  });

  it.each([
    { price: -1, discount: 0 },
    { price: 100, discount: -1 },
    { price: 0, discount: 1 },
    { price: 100, discount: 101 },
    { price: 100.5, discount: 0 },
    { price: 100, discount: 0.5 },
    // Equal fractional/unsafe inputs still fail even when their difference is zero.
    { price: 0.5, discount: 0.5 },
    { price: 9007199254740992, discount: 9007199254740992 },
    { price: 9007199254740992, discount: 0 },
    { price: 9007199254740991, discount: 9007199254740992 },
    { price: Number.NaN, discount: 0 },
    { price: 100, discount: Number.NaN },
    { price: Number.POSITIVE_INFINITY, discount: 0 },
    { price: 100, discount: Number.POSITIVE_INFINITY },
    { price: Number.NEGATIVE_INFINITY, discount: 0 },
    { price: 100, discount: Number.NEGATIVE_INFINITY },
  ])('rejects invalid inputs $price and $discount with RangeError', ({ price, discount }) => {
    expect(() => membershipNetPrice(price, discount)).toThrow(RangeError);
  });
});
