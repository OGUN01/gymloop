import { rupeesFromPaise } from '../api/payments';
import { toLocalDate } from '../streaks/streaks';

/**
 * People-facing display helpers (ADR-170, UX9-003): money, vocabularies, phones and
 * dates as a person reads them. Platform-free so web and native share one voice.
 */

/** Exact paise as "₹8,000" / "₹1,500.50" with Indian grouping; other currencies keep their code. */
export function formatMoney(paise: number | string, currency = 'INR'): string {
  const exact = rupeesFromPaise(paise);
  const negative = exact.startsWith('-');
  const [whole = '0', fraction = '00'] = exact.replace('-', '').split('.');
  // String grouping, not Intl on BigInt: Hermes (Android) cannot format BigInt, and money must stay exact.
  const grouped = currency === 'INR' ? whole.replace(/(\d)(?=(\d\d)+\d$)/g, '$1,') : whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  const sign = negative ? '-' : '';
  if (currency !== 'INR') return `${sign}${currency} ${grouped}.${fraction}`;
  return `${sign}₹${grouped}${/^0+$/.test(fraction) ? '' : `.${fraction}`}`;
}

const WORDS: Record<string, string> = {
  upi: 'UPI', sms: 'SMS', whatsapp: 'WhatsApp', razorpay: 'Razorpay', pt: 'PT', qr: 'QR', gst: 'GST', id: 'ID', otp: 'OTP',
};

/** A vocabulary value ("no_response", "whatsappBusiness") as sentence-case words ("No response", "WhatsApp Business"). */
export function humanize(value: string): string {
  if (value === 'follow_up_due') return 'Follow-up due';
  const words = value.replace(/([a-z])([A-Z])/g, '$1 $2').split(/[_\s-]+/).filter(Boolean)
    .map((word) => word.toLowerCase());
  const branded = words.some((word) => word === 'whatsapp');
  return words.map((word, index) => {
    const known = WORDS[word];
    if (known) return known;
    if (branded && word === 'business') return 'Business';
    return index === 0 ? `${word.charAt(0).toUpperCase()}${word.slice(1)}` : word;
  }).join(' ');
}

/** Indian mobile numbers read in two groups of five ("+91 98765 00001"); anything else is shown as stored. */
export function formatPhone(value: string): string {
  const northAmerican = /^\+1(\d{3})(\d{3})(\d{4})$/.exec(value);
  if (northAmerican) return `+1 ${northAmerican[1]}-${northAmerican[2]}-${northAmerican[3]}`;
  const match = /^(\+91)?(\d{5})(\d{5})$/.exec(value);
  if (!match) return value;
  return [match[1], match[2], match[3]].filter(Boolean).join(' ');
}

const MONTH = new Intl.DateTimeFormat('en-US', { month: 'short', timeZone: 'UTC' });
const parts = (isoDate: string) => {
  const date = new Date(`${isoDate}T12:00:00Z`);
  return { day: date.getUTCDate(), month: MONTH.format(date), year: date.getUTCFullYear() };
};

/** A calendar date ("2026-09-21") as "21 Sep 2026". */
export function formatDay(isoDate: string): string {
  const { day, month, year } = parts(isoDate);
  return `${day} ${month} ${year}`;
}

/** An instant in the gym's timezone as "21 Sep 2026, 4:36 pm". */
export function formatDateTime(instant: string | Date, timeZone: string): string {
  const date = new Date(instant);
  const day = new Intl.DateTimeFormat('en-CA', { year: 'numeric', month: '2-digit', day: '2-digit', timeZone }).format(date);
  const time = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', timeZone }).format(date).toLowerCase();
  return `${formatDay(day)}, ${time}`;
}

/** Two calendar dates as the shortest unambiguous range ("1–24 Sep 2026", "28 Aug – 24 Sep 2026"). */
export function formatDayRange(from: string, through: string): string {
  if (from === through) return formatDay(from);
  const start = parts(from);
  const end = parts(through);
  if (start.year !== end.year) return `${formatDay(from)} – ${formatDay(through)}`;
  if (start.month !== end.month) return `${start.day} ${start.month} – ${formatDay(through)}`;
  return `${start.day}–${formatDay(through)}`;
}

/** Items grouped by calendar month in `timeZone`, newest-first order preserved; the label drops the year for the current year ("September", "August 2025"). */
export function groupByMonth<T>(items: readonly T[], instantOf: (item: T) => string, timeZone: string, now: Date = new Date()): { key: string; label: string; items: T[] }[] {
  // Keys come from date parts (toLocalDate uses formatToParts): Hermes formats en-CA year-month as "09/2026", not "2026-09".
  const currentYear = toLocalDate(now, timeZone).slice(0, 'YYYY'.length);
  const months: { key: string; label: string; items: T[] }[] = [];
  for (const item of items) {
    const at = new Date(instantOf(item));
    const key = toLocalDate(at, timeZone).slice(0, 'YYYY-MM'.length);
    const month = months.at(-1);
    if (month?.key === key) month.items.push(item);
    else months.push({ key, label: at.toLocaleDateString('en-GB', { month: 'long', timeZone }) + (key.startsWith(currentYear) ? '' : ` ${key.slice(0, 'YYYY'.length)}`), items: [item] });
  }
  return months;
}
