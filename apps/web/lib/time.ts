import { DEFAULT_TIMEZONE } from '@gymloop/shared';

/**
 * An instant as the GYM reads it: `2026-09-09 03:00`, in the gym's own
 * timezone and never the server's.
 *
 * Seconds are dropped deliberately. Nobody reconciling a drawer cares which
 * second, and a narrower column fits a receipt.
 */
export function deskTime(iso: string, timezone: string): string {
  const at = (zone: string) => {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: zone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      // `h23` and not `hour12: false`, which renders midnight as `24` under
      // some ICU versions — a receipt dated 24:07 is a receipt nobody trusts.
      hourCycle: 'h23',
    }).formatToParts(new Date(iso));
    const part = (type: string) => parts.find((value) => value.type === type)?.value ?? '';
    return `${part('year')}-${part('month')}-${part('day')} ${part('hour')}:${part('minute')}`;
  };

  try {
    return at(timezone);
  } catch {
    // `organizations.timezone` is free text, so a gym can hold a name `Intl`
    // does not know. Keep the receipt usable with the platform default.
    return at(DEFAULT_TIMEZONE);
  }
}

/** Label gym-local instants without attributing a fallback time to an invalid zone. */
export function gymTimeLabel(iso: string, timezone: string): string {
  try {
    new Intl.DateTimeFormat('en-CA', { timeZone: timezone }).format(new Date(iso));
    return `${deskTime(iso, timezone)} · ${timezone}`;
  } catch {
    return 'Gym timezone unavailable';
  }
}
