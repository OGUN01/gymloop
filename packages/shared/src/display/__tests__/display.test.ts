import { describe, expect, it } from 'vitest';
import { formatDateTime, formatDay, formatDayRange, formatMoney, formatPhone, humanize } from '../display';

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
    ['+14155550100', '+14155550100'],
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
