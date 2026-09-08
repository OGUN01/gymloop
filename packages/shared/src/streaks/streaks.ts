import { DAYS_PER_WEEK, MS_PER_DAY } from '../config/constants';

/**
 * Streak computation (STK-001, STK-002) — pure, no I/O, no database.
 *
 * The caller supplies every fact: the member's visits, their rest days, the
 * gym's approved pauses and holidays, the rule's parameters, and the gym's
 * timezone. That is what lets the same code run in a Route Handler, in an
 * Edge Function and in the mobile app, and what lets the whole thing be
 * tested without a database.
 *
 * **Everything here is evaluated in the gym's timezone (MNY-004).** A visit
 * recorded at 2026-09-08T19:00:00Z is 00:30 on the 9th in Asia/Kolkata: in
 * UTC it lands on the 8th, and a streak computed in UTC is wrong for five and
 * a half hours of every day — which is real gym traffic, not an edge case.
 * The same trap as `current_date` in Postgres (docs/data-model.md, `=today_ist`).
 * Every instant is therefore first collapsed to a gym-local calendar day, and
 * all arithmetic after that is on whole days.
 *
 * **The three rule types are three exported functions, not one function with a
 * `rule` parameter.** `streak_rule_type` is a Postgres enum, and ADR-021 says
 * a status vocabulary is never re-declared as a TypeScript union — this package
 * cannot import `@gymloop/db`, so the switch belongs at the call site, where
 * the generated enum type is available and exhaustiveness is checked against
 * the real vocabulary.
 */

/** A calendar day in the gym's own timezone, `YYYY-MM-DD`. Never an instant. */
export type LocalDate = string;

/**
 * A `membership_pauses` row as it comes out of the database. Both timestamps
 * are carried rather than a pre-computed boolean so a caller cannot forget
 * STK-002's qualifier: **approved** means `approved_at` set and `rejected_at`
 * null, and that test is applied here, once.
 */
export interface StreakPause {
  startsOn: LocalDate;
  endsOn: LocalDate;
  approvedAt: string | null;
  rejectedAt: string | null;
}

export interface StreakInput {
  /** `attendance.checked_in_at` instants. Several visits in one day count once. */
  visits: readonly (string | Date)[];
  /** "Now" as an instant — the caller passes it, so the function stays pure. */
  asOf: string | Date;
  /** IANA zone: `branches.timezone` if set, else `organizations.timezone`. */
  timeZone: string;
  /** `members.rest_days`, weekday numbers with 0 = Sunday (STK-002). */
  restDays?: readonly number[] | undefined;
  /** `organization_holidays.holiday_on` — a holiday is never a streak break. */
  holidays?: readonly LocalDate[] | undefined;
  /** `membership_pauses` rows; only approved ones are honoured (STK-002). */
  pauses?: readonly StreakPause[] | undefined;
}

export interface WeeklyGoalStreakInput extends StreakInput {
  /** `members.weekly_goal_visits` ?? `organization_settings.weekly_goal_default`. */
  goal: number;
  /** `organization_settings.week_start_day`, 0 = Sunday. */
  weekStartDay: number;
}

export interface CalendarStreakInput extends StreakInput {
  /** The challenge period. Days outside it are not looked at at all. */
  startsOn: LocalDate;
  endsOn: LocalDate;
}

export interface StreakResult {
  /** The streak running now. Counted in `unit`s. */
  current: number;
  /** The best run in the range examined, which is bounded by `visits`. */
  longest: number;
  /** What `current`/`longest` count, so a UI cannot mislabel weeks as days. */
  unit: 'day' | 'week';
  /**
   * What broke a streak: the day itself for a day rule, the week's start date
   * for the weekly goal. Rest days, holidays, approved pauses and the current
   * day/week are never here — they do not break anything (STK-002).
   */
  missed: readonly LocalDate[];
}

function dayFormatter(timeZone: string): Intl.DateTimeFormat {
  return new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
}

/**
 * Assembled from parts rather than from a locale that happens to print
 * `YYYY-MM-DD` (`en-CA`), because the part types are specified and the output
 * format of a locale is not — and this has to hold on whatever `Intl` the
 * mobile runtime ships.
 */
function formatDay(fmt: Intl.DateTimeFormat, at: Date): LocalDate {
  let year = '';
  let month = '';
  let day = '';
  for (const { type, value } of fmt.formatToParts(at)) {
    if (type === 'year') year = value;
    else if (type === 'month') month = value;
    else if (type === 'day') day = value;
  }
  return `${year}-${month}-${day}`;
}

/** The gym-local calendar day an instant falls on (MNY-004). */
export function toLocalDate(instant: string | Date, timeZone: string): LocalDate {
  return formatDay(dayFormatter(timeZone), new Date(instant));
}

const UTC_DAY_FORMATTER = dayFormatter('UTC');

/**
 * A calendar day as a whole number of days since the epoch. Anchoring the
 * arithmetic at UTC midnight is what makes it DST-proof: the local day was
 * already decided by `Intl` above, and from here on a day is just an integer,
 * never "24 hours later" in a zone where some days are 23 or 25 hours long.
 */
function dayNumber(day: LocalDate): number {
  const [year = 0, month = 1, dayOfMonth = 1] = day.split('-').map(Number);
  return Date.UTC(year, month - 1, dayOfMonth) / MS_PER_DAY;
}

function localDate(dayNo: number): LocalDate {
  return formatDay(UTC_DAY_FORMATTER, new Date(dayNo * MS_PER_DAY));
}

function weekday(dayNo: number): number {
  return new Date(dayNo * MS_PER_DAY).getUTCDay();
}

function visitedDays(input: StreakInput, fmt: Intl.DateTimeFormat): Set<number> {
  return new Set(input.visits.map((at) => dayNumber(formatDay(fmt, new Date(at)))));
}

/** STK-002: a rest day, a gym holiday, or an approved pause is not a break. */
function exemptChecker(input: StreakInput): (dayNo: number) => boolean {
  const restDays = new Set(input.restDays ?? []);
  const holidays = new Set((input.holidays ?? []).map(dayNumber));
  const pauses = (input.pauses ?? [])
    .filter((pause) => pause.approvedAt !== null && pause.rejectedAt === null)
    .map((pause) => ({ from: dayNumber(pause.startsOn), to: dayNumber(pause.endsOn) }));
  return (dayNo) =>
    restDays.has(weekday(dayNo)) ||
    holidays.has(dayNo) ||
    pauses.some((pause) => dayNo >= pause.from && dayNo <= pause.to);
}

function empty(unit: StreakResult['unit']): StreakResult {
  return { current: 0, longest: 0, unit, missed: [] };
}

/**
 * The day-by-day core, shared by the visit streak and the calendar streak —
 * they differ only in which range of days they look at.
 *
 * Today never breaks a streak: the member may still be coming in this evening.
 * It counts as soon as they do.
 */
function scanDays(
  from: number,
  to: number,
  visited: Set<number>,
  exempt: (dayNo: number) => boolean,
  today: number,
): StreakResult {
  let run = 0;
  let longest = 0;
  const missed: LocalDate[] = [];
  for (let dayNo = from; dayNo <= to; dayNo += 1) {
    if (visited.has(dayNo)) {
      run += 1;
      continue;
    }
    if (exempt(dayNo) || dayNo === today) continue;
    missed.push(localDate(dayNo));
    longest = Math.max(longest, run);
    run = 0;
  }
  return { current: run, longest: Math.max(longest, run), unit: 'day', missed };
}

/**
 * STK-001 visit streak: consecutive days attended, from the member's first
 * visit to today. The range is bounded by the visits the caller fetched, so a
 * caller that wants a shorter history simply passes fewer visits.
 */
export function visitStreak(input: StreakInput): StreakResult {
  const fmt = dayFormatter(input.timeZone);
  const visited = visitedDays(input, fmt);
  if (visited.size === 0) return empty('day');
  const today = dayNumber(formatDay(fmt, new Date(input.asOf)));
  const from = Math.min(today, ...visited);
  return scanDays(from, today, visited, exemptChecker(input), today);
}

/**
 * STK-001 calendar streak: consecutive days inside one challenge period.
 * Nothing outside `[startsOn, endsOn]` is considered, and the period is
 * clamped at today — a challenge that has not started yet has no streak, and
 * days the member has not reached yet are not misses.
 */
export function calendarStreak(input: CalendarStreakInput): StreakResult {
  const fmt = dayFormatter(input.timeZone);
  const today = dayNumber(formatDay(fmt, new Date(input.asOf)));
  const from = dayNumber(input.startsOn);
  const to = Math.min(dayNumber(input.endsOn), today);
  if (to < from) return empty('day');
  return scanDays(from, to, visitedDays(input, fmt), exemptChecker(input), today);
}

/**
 * STK-001 weekly goal: N visits per week, counted in **weeks**, not days.
 *
 * A week the member could not have met is skipped rather than broken — if an
 * approved pause, the rest days and the holidays between them leave fewer than
 * `goal` days available, the week bridges the streak instead of ending it,
 * which is STK-002 applied at the granularity this rule actually counts in.
 * The week in progress is the same: it counts the moment the goal is reached,
 * and never breaks anything before it is over.
 */
export function weeklyGoalStreak(input: WeeklyGoalStreakInput): StreakResult {
  const fmt = dayFormatter(input.timeZone);
  const visited = visitedDays(input, fmt);
  if (visited.size === 0) return empty('week');
  const exempt = exemptChecker(input);
  const startOfWeek = (dayNo: number): number =>
    dayNo -
    ((((weekday(dayNo) - input.weekStartDay) % DAYS_PER_WEEK) + DAYS_PER_WEEK) % DAYS_PER_WEEK);

  const thisWeek = startOfWeek(dayNumber(formatDay(fmt, new Date(input.asOf))));
  const firstWeek = Math.min(thisWeek, startOfWeek(Math.min(...visited)));
  let run = 0;
  let longest = 0;
  const missed: LocalDate[] = [];
  for (let week = firstWeek; week <= thisWeek; week += DAYS_PER_WEEK) {
    let attended = 0;
    let available = 0;
    for (let dayNo = week; dayNo < week + DAYS_PER_WEEK; dayNo += 1) {
      if (visited.has(dayNo)) attended += 1;
      if (!exempt(dayNo)) available += 1;
    }
    if (attended >= input.goal) {
      run += 1;
      continue;
    }
    if (week === thisWeek || available < input.goal) continue;
    missed.push(localDate(week));
    longest = Math.max(longest, run);
    run = 0;
  }
  return { current: run, longest: Math.max(longest, run), unit: 'week', missed };
}
