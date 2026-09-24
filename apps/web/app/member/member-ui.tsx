import { DAYS_PER_WEEK, GREETING_HOURS, formatDay, toLocalDate } from '@gymloop/shared';
import type { ReactNode } from 'react';

type Visit = { checked_in_at: string };

/** The gym's own name without its branch suffix, as members say it. */
export function memberGymName(gym: { name: string; branchName: string }): string {
  const branchSuffix = ` — ${gym.branchName}`;
  return gym.name.endsWith(branchSuffix) ? gym.name.slice(0, -branchSuffix.length) : gym.name;
}

/** Time-of-day greeting in the gym's timezone. */
export function memberGreeting(timezone: string, now = new Date()): string {
  const hour = Number(new Intl.DateTimeFormat('en-IN', { hour: 'numeric', hourCycle: 'h23', timeZone: timezone }).format(now));
  return hour < GREETING_HOURS.afternoon ? 'Good morning' : hour < GREETING_HOURS.evening ? 'Good afternoon' : 'Good evening';
}

/** A calendar date ("2026-10-12") as "12 Oct". */
export function memberShortDate(isoDate: string): string {
  return formatDay(isoDate).replace(/ \d{4}$/, '');
}


/** The attendance row for the same week the "N of goal" count uses; falls back to the last seven days. */
export function MemberWeekRhythm({ visits, timezone, weekStart, tone = 'accent' }: { visits: readonly Visit[]; timezone: string; weekStart?: string | undefined; tone?: 'accent' | 'ink' }): ReactNode {
  const today = toLocalDate(new Date(), timezone);
  const visited = new Set(visits.map((visit) => toLocalDate(visit.checked_in_at, timezone)));
  const first = new Date(`${weekStart ?? today}T12:00:00Z`);
  if (weekStart === undefined) first.setUTCDate(first.getUTCDate() - (DAYS_PER_WEEK - 1));
  const days = Array.from({ length: DAYS_PER_WEEK }, (_, index) => {
    const day = new Date(first);
    day.setUTCDate(first.getUTCDate() + index);
    const key = day.toISOString().slice(0, 'YYYY-MM-DD'.length);
    return { key, label: day.toLocaleDateString('en-GB', { weekday: 'short', timeZone: 'UTC' }).slice(0, 1), name: day.toLocaleDateString('en-GB', { weekday: 'long', timeZone: 'UTC' }), visited: visited.has(key), future: key > today, today: key === today };
  });
  return <div className="member-week-days" data-tone={tone} role="list" aria-label={weekStart ? 'This week' : 'Last seven days'}>
    {days.map((day) => <span className="member-week-day" role="listitem" data-visited={day.visited} data-future={day.future} data-today={day.today} aria-label={`${day.name}: ${day.visited ? 'visited' : day.future ? 'still ahead' : 'no visit'}`} key={day.key}><i aria-hidden="true" /><span aria-hidden="true">{day.label}</span></span>)}
  </div>;
}
