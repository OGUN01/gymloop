import { describe, expect, it } from 'vitest';
import { formatDateTime, formatDay, formatDayRange, formatMoney, formatPhone, groupByMonth, humanize } from '../display';

// UX9-003/005 (ADR-170): people see money, vocabularies, phones and dates as words, never raw values.
describe('formatMoney', () => {
  it.each([
    ['800000', 'INR', '₹8,000'],
    ['150050', 'INR', '₹1,500.50'],
    ['0', 'INR', '₹0'],
    ['-150000', 'INR', '-₹1,500'],
    ['4330000', 'INR', '₹43,300'],
    ['9007199254740993', 'INR', '₹9,00,71,99,25,47,409.93'],
    ['120000', 'USD', 'USD 1,200.00'],
  ])('formats %s %s as %s', (paise, currency, expected) => {
    expect(formatMoney(paise, currency)).toBe(expected);
  });
  it('defaults to rupees and keeps the exact paise contract of rupeesFromPaise', () => {
    expect(formatMoney(1)).toBe('₹0.01');
    expect(() => formatMoney('1.5')).toThrow(TypeError);
  });
});

describe('humanize', () => {
  it.each([
    ['no_response', 'No response'], ['upi', 'UPI'], ['sms', 'SMS'], ['whatsapp', 'WhatsApp'],
    ['whatsapp_business', 'WhatsApp Business'], ['whatsappBusiness', 'WhatsApp Business'], ['razorpay', 'Razorpay'],
    ['follow_up_due', 'Follow-up due'], ['front_desk_form', 'Front desk form'], ['pt_package', 'PT package'],
    ['in_app', 'In app'], ['active', 'Active'], ['', ''],
  ])('says %j as %j', (value, expected) => {
    expect(humanize(value)).toBe(expected);
  });
});

describe('formatPhone', () => {
  it.each([
    ['+919876500001', '+91 98765 00001'],
    ['9876500001', '98765 00001'],
    ['+14155550100', '+1 415-555-0100'],
    ['+447700900123', '+447700900123'],
    ['', ''],
  ])('shows %j as %j', (value, expected) => {
    expect(formatPhone(value)).toBe(expected);
  });
});

describe('dates', () => {
  it('formats a calendar day with a three-letter month', () => {
    expect(formatDay('2026-09-21')).toBe('21 Sep 2026');
  });
  it('formats an instant in the gym timezone', () => {
    expect(formatDateTime('2026-09-21T11:06:00Z', 'Asia/Kolkata')).toBe('21 Sep 2026, 4:36 pm');
  });
  it.each([
    ['2026-09-01', '2026-09-24', '1–24 Sep 2026'],
    ['2026-08-28', '2026-09-24', '28 Aug – 24 Sep 2026'],
    ['2025-12-20', '2026-01-05', '20 Dec 2025 – 5 Jan 2026'],
    ['2026-09-24', '2026-09-24', '24 Sep 2026'],
  ])('formats the range %s to %s', (from, through, expected) => {
    expect(formatDayRange(from, through)).toBe(expected);
  });
});

describe('groupByMonth', () => {
  it('groups consecutive items by month in the gym time zone and names past years', () => {
    const at = ['2026-09-21T18:40:00Z', '2026-09-01T03:00:00Z', '2026-08-31T19:00:00Z', '2025-12-31T20:00:00Z'];
    const groups = groupByMonth(at, (item) => item, 'Asia/Kolkata', new Date('2026-09-24T00:00:00Z'));
    // 2026-08-31T19:00Z is 1 Sep in IST; 2025-12-31T20:00Z is 1 Jan 2026 in IST.
    expect(groups.map((group) => [group.label, group.items.length])).toEqual([['September', 3], ['January', 1]]);
  });
});

describe('groupByMonth on engines without ISO en-CA dates (Hermes)', () => {
  it('keys and labels months from date parts, not from a locale string shape', () => {
    const original = Date.prototype.toLocaleDateString;
    // Hermes returns "09/2026" for en-CA { year, month: '2-digit' }; the grouping must not depend on that shape.
    const hermesLike = function (this: Date, locale?: Intl.LocalesArgument, options?: Intl.DateTimeFormatOptions) {
      if (locale === 'en-CA') return original.call(this, 'en-US', options);
      return original.call(this, locale, options);
    };
    Date.prototype.toLocaleDateString = hermesLike as typeof Date.prototype.toLocaleDateString;
    try {
      const groups = groupByMonth(['2026-09-21T18:40:00Z', '2025-08-10T06:00:00Z'], (item) => item, 'Asia/Kolkata', new Date('2026-09-24T00:00:00Z'));
      expect(groups.map((group) => [group.key, group.label])).toEqual([['2026-09', 'September'], ['2025-08', 'August 2025']]);
    } finally {
      Date.prototype.toLocaleDateString = original;
    }
  });
});
