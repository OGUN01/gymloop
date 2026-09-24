import { DAYS_PER_WEEK, GREETING_HOURS, toLocalDate } from '@gymloop/shared';
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
  return new Intl.DateTimeFormat('en-IN', { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(`${isoDate}T12:00:00Z`));
}


/** The truthful last-seven-days attendance row, shared by Home and Activity. */
export function MemberWeekRhythm({ visits, timezone, tone = 'accent' }: { visits: readonly Visit[]; timezone: string; tone?: 'accent' | 'ink' }): ReactNode {
  const today = toLocalDate(new Date(), timezone);
  const visited = new Set(visits.map((visit) => toLocalDate(visit.checked_in_at, timezone)));
  const days = Array.from({ length: DAYS_PER_WEEK }, (_, index) => {
    const day = new Date(`${today}T12:00:00Z`);
    day.setUTCDate(day.getUTCDate() - (DAYS_PER_WEEK - 1 - index));
    const key = day.toISOString().slice(0, 'YYYY-MM-DD'.length);
    return { key, label: day.toLocaleDateString('en-IN', { weekday: 'narrow', timeZone: 'UTC' }), name: day.toLocaleDateString('en-IN', { weekday: 'long', timeZone: 'UTC' }), visited: visited.has(key) };
  });
  return <div className="member-week-days" data-tone={tone} role="list" aria-label="Last seven days">
    {days.map((day) => <span className="member-week-day" role="listitem" data-visited={day.visited} aria-label={`${day.name}: ${day.visited ? 'visited' : 'no visit'}`} key={day.key}><i aria-hidden="true" /><span aria-hidden="true">{day.label}</span></span>)}
  </div>;
}
