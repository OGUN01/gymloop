/** Frozen OCC-001…017 analytics contract (occupancy-analytics proposal, frozen
 * 2026-10-03). Pure, platform-free derivations over caller-supplied rows: the
 * web loader assembles one snapshot response and these helpers turn its
 * populations into the disclosed exact figures. Money is integer paise moved
 * as canonical decimal strings and summed with BigInt — never float, never
 * Number() on money. OCC_LIMITS itself lives in config/constants.ts. */
import { OCC_LIMITS } from '../config/constants';

export { OCC_LIMITS };

export type RangeBounds =
  | { startInstant: string; endInstant: string; zone: string }
  | { error: string };

const HOUR_MS = 3_600_000;
const HOURS_PER_DAY = 24;
const MIDNIGHT_FIXUP_PASSES = 4;
const ISO_DAY_LENGTH = 10;
const FRACTION_SCALE = 10_000n;
const FRACTION_DECIMALS = 4;
const CLOCK_DIGITS = 2;

type ZonedParts = { year: number; month: number; day: number; hour: number; minute: number };

const wallFormatterCache = new Map<string, Intl.DateTimeFormat>();
const zoneValidatorCache = new Map<string, boolean>();

function pad2(value: number): string {
  return String(value).padStart(CLOCK_DIGITS, '0');
}

function wallFormatter(timeZone: string): Intl.DateTimeFormat {
  let formatter = wallFormatterCache.get(timeZone);
  if (formatter === undefined) {
    formatter = new Intl.DateTimeFormat('en-GB', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      weekday: 'short',
      hourCycle: 'h23',
    });
    wallFormatterCache.set(timeZone, formatter);
  }
  return formatter;
}

function zonedWall(instantMs: number, timeZone: string): ZonedParts {
  const parts = wallFormatter(timeZone).formatToParts(new Date(instantMs));
  const read = (type: string): number => Number(parts.find((part) => part.type === type)?.value ?? '0');
  return { year: read('year'), month: read('month'), day: read('day'), hour: read('hour'), minute: read('minute') };
}

function isValidZone(timeZone: string): boolean {
  const cached = zoneValidatorCache.get(timeZone);
  if (cached !== undefined) return cached;
  try {
    const probe = new Intl.DateTimeFormat('en', { timeZone });
    const valid = probe.resolvedOptions().timeZone !== undefined;
    zoneValidatorCache.set(timeZone, valid);
    return valid;
  } catch {
    zoneValidatorCache.set(timeZone, false);
    return false;
  }
}

function isoDayParts(localDate: string): [number, number, number] {
  const parts = localDate.split('-').map(Number);
  return [parts[0] ?? 0, parts[1] ?? 0, parts[2] ?? 0];
}

function isValidIsoDay(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = isoDayParts(value);
  const probe = new Date(Date.UTC(year, month - 1, day));
  return probe.getUTCFullYear() === year && probe.getUTCMonth() === month - 1 && probe.getUTCDate() === day;
}

/** The UTC instant of local midnight for a calendar date in a zone, resolved against DST (iterative offset fix-up). */
export function localMidnightInstant(localDate: string, timeZone: string): number {
  const [year, month, day] = isoDayParts(localDate);
  const target = Date.UTC(year, month - 1, day, 0, 0, 0);
  let guess = target;
  for (let pass = 0; pass < MIDNIGHT_FIXUP_PASSES; pass += 1) {
    const wall = zonedWall(guess, timeZone);
    if (wall.year === year && wall.month === month && wall.day === day && wall.hour === 0 && wall.minute === 0) {
      return guess;
    }
    const wallAsUtc = Date.UTC(wall.year, wall.month - 1, wall.day, wall.hour, wall.minute);
    guess = target - (wallAsUtc - guess);
  }
  return guess;
}

function nextIsoDay(localDate: string): string {
  const [year, month, day] = isoDayParts(localDate);
  return new Date(Date.UTC(year, month - 1, day + 1)).toISOString().slice(0, ISO_DAY_LENGTH);
}

/** OCC-007's default arrival range: the `defaultRangeDays` days ending at the given day (inclusive). */
export function occupancyDefaultRangeFrom(throughIsoDay: string): string {
  const [year, month, day] = isoDayParts(throughIsoDay);
  return new Date(Date.UTC(year, month - 1, day - (OCC_LIMITS.defaultRangeDays - 1))).toISOString().slice(0, ISO_DAY_LENGTH);
}

/** A two-digit rendering for clock labels ("07:00"), kept beside the analytics vocabulary. */
export function twoDigit(value: number): string {
  return String(value).padStart(CLOCK_DIGITS, '0');
}

/** The calendar-day part of an instant as an ISO day. */
export function isoDayOfInstant(instantMs: number): string {
  return new Date(instantMs).toISOString().slice(0, ISO_DAY_LENGTH);
}

export function isoDayOfWeek(localDate: string): number {
  const [year, month, day] = isoDayParts(localDate);
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay();
}

/** OCC-003: an inclusive calendar range becomes [local midnight from, local midnight after through) in one zone. */
export function occupancyRangeBounds(from: string, through: string, timeZone: string): RangeBounds {
  if (!isValidIsoDay(from) || !isValidIsoDay(through)) return { error: 'invalid_range' };
  if (from > through) return { error: 'reversed_range' };
  if (!isValidZone(timeZone)) return { error: 'invalid_time_zone' };
  return {
    startInstant: new Date(localMidnightInstant(from, timeZone)).toISOString(),
    endInstant: new Date(localMidnightInstant(nextIsoDay(through), timeZone)).toISOString(),
    zone: timeZone,
  };
}

/** OCC-006: a local date is completed when its next local midnight is at or before asOf. */
export function isCompletedLocalDate(localDate: string, asOfInstant: string, timeZone: string): boolean {
  return Date.parse(asOfInstant) >= localMidnightInstant(nextIsoDay(localDate), timeZone);
}

const WEEKDAY_INDEX: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };

export type ArrivalBucket = { localDate: string; weekday: number; hour: number };

/** OCC-004: one accepted visit lands in exactly one branch-local date/weekday/clock-hour bucket. */
export function arrivalBucket(instant: string, timeZone: string): ArrivalBucket {
  const parts = wallFormatter(timeZone).formatToParts(new Date(Date.parse(instant)));
  const text = (type: string): string => parts.find((part) => part.type === type)?.value ?? '';
  const weekdayShort = text('weekday');
  return {
    localDate: `${text('year')}-${text('month')}-${text('day')}`,
    weekday: WEEKDAY_INDEX[weekdayShort] ?? -1,
    hour: Number(text('hour')) % HOURS_PER_DAY,
  };
}

/** The exact truncated decimal of a ratio ("0.0714…") — BigInt only, the ellipsis marks the hidden remainder. */
export function exactFractionText(numerator: bigint | number, denominator: bigint | number): string | null {
  const den = BigInt(denominator);
  if (den === BigInt(0)) return null;
  const scaled = BigInt(numerator) * FRACTION_SCALE;
  const negative = scaled < BigInt(0) !== den < BigInt(0);
  const quotient = (negative ? -scaled : scaled) / (negative ? -den : den);
  const whole = quotient / FRACTION_SCALE;
  const decimals = (quotient % FRACTION_SCALE).toString().padStart(FRACTION_DECIMALS, '0');
  return `${negative ? '-' : ''}${whole}.${decimals}…`;
}

export type ArrivalRow = {
  localDate: string;
  weekday: number;
  hour: number;
  isHoliday?: boolean;
  incomplete?: boolean;
};

export type HeatmapCell = {
  weekday: number;
  hour: number;
  arrivals: number;
  todayArrivals: number;
  eligibleDates: number;
  fraction: string | null;
  limited: boolean;
  message: string | null;
};

export type HeatmapExposure = {
  cells: HeatmapCell[];
  eligibleDateCount: number;
  noEligibleDays: boolean;
  message: string | null;
};

/** Does local clock hour `hour` exist on this date in this zone (DST spring-forward gaps do not)? */
function localHourExists(localDate: string, hour: number, timeZone: string): boolean {
  const candidate = localMidnightInstant(localDate, timeZone) + hour * HOUR_MS;
  const wall = zonedWall(candidate, timeZone);
  return wall.hour === hour && `${wall.year}-${pad2(wall.month)}-${pad2(wall.day)}` === localDate;
}

/** OCC-004…008: exact per-weekday/hour exposure over eligible completed local dates. */
export function heatmapExposure(arrivals: ReadonlyArray<ArrivalRow>, options: {
  excludeHolidays: boolean;
  completedThroughInstant: string;
  timeZone: string;
  eligibleDates?: ReadonlyArray<string>;
}): HeatmapExposure {
  const holidayDates = new Set(arrivals.filter((row) => row.isHoliday === true).map((row) => row.localDate));
  const provided = options.eligibleDates;
  const candidateDates = provided !== undefined
    ? [...provided]
    : [...new Set(arrivals.map((row) => row.localDate))];
  const eligible = candidateDates.filter((date) =>
    isCompletedLocalDate(date, options.completedThroughInstant, options.timeZone) &&
    !(options.excludeHolidays && holidayDates.has(date)));
  const denominator = eligible.length;
  if (denominator === 0) {
    return { cells: [], eligibleDateCount: 0, noEligibleDays: true, message: 'No eligible days' };
  }
  const limited = denominator < OCC_LIMITS.minHeatmapEligibleDates;
  const existingKeys = new Set<string>();
  for (const date of eligible) {
    const weekday = isoDayOfWeek(date);
    for (let hour = 0; hour < HOURS_PER_DAY; hour += 1) {
      if (localHourExists(date, hour, options.timeZone)) existingKeys.add(`${weekday}:${hour}`);
    }
  }
  const counters = new Map<string, { arrivals: number; todayArrivals: number }>();
  const bucketOf = (row: ArrivalRow): string | null => {
    const key = `${row.weekday}:${row.hour}`;
    return existingKeys.has(key) ? key : null;
  };
  for (const row of arrivals) {
    if (options.excludeHolidays && row.isHoliday === true) continue;
    const key = bucketOf(row);
    if (key === null) continue;
    const cell = counters.get(key) ?? { arrivals: 0, todayArrivals: 0 };
    if (row.incomplete === true) cell.todayArrivals += 1;
    else cell.arrivals += 1;
    counters.set(key, cell);
  }
  const cells: HeatmapCell[] = [...existingKeys].map((key) => {
    const keyParts = key.split(':').map(Number);
    const weekday = keyParts[0] ?? 0;
    const hour = keyParts[1] ?? 0;
    const counted = counters.get(key) ?? { arrivals: 0, todayArrivals: 0 };
    const fraction = counted.arrivals === 0 || limited ? null : exactFractionText(counted.arrivals, denominator);
    return {
      weekday,
      hour,
      arrivals: counted.arrivals,
      todayArrivals: counted.todayArrivals,
      eligibleDates: denominator,
      fraction,
      limited,
      message: limited ? 'Limited history' : null,
    };
  }).sort((left, right) => left.weekday - right.weekday || left.hour - right.hour);
  return { cells, eligibleDateCount: denominator, noEligibleDays: false, message: null };
}

export type CollectionPaymentRow = {
  paymentId: string;
  amountPaise: string;
  currency: string;
  status: string;
  paidAt: string | null;
  membershipId: string | null;
  addonOrderId: string | null;
};

export type CollectionReturnRow = {
  returnId: string;
  status: string;
  processedAt: string | null;
  amountPaise: string;
  currency: string;
  originalPaymentId?: string | null;
};

export type CollectionMembershipRow = {
  membershipId: string;
  memberId: string;
  createdAt: string;
};

export type ClassificationBreakdown = {
  newMemberPaise: string;
  renewalPaise: string;
  addonPaise: string;
  unallocatedPaise: string;
  unknownReturnPaise: string;
  label: string;
};

export type CollectionMonth = {
  month: string;
  currency: string;
  collectedPaise: string;
  returnedPaise: string;
  netPaise: string;
  classification: ClassificationBreakdown;
};

export type ClassifiedCollection = {
  months: CollectionMonth[];
  warnings: {
    undatedPayments: Array<{ paymentId: string; amountPaise: string; currency: string }>;
    undatedReturns: Array<{ returnId: string; amountPaise: string; currency: string }>;
  };
};

const ARRIVED_STATUSES = new Set(['paid', 'refunded', 'reversed']);
const ZERO = BigInt(0);
const CLASSIFICATION_LABEL = 'Membership linkage (derived classification)';

/** OCC-012: a payment classifies whole by its membership linkage; nothing is guessed for unlinked rows. */
function firstMembershipIds(memberships: ReadonlyArray<CollectionMembershipRow>): Set<string> {
  const firstByMember = new Map<string, CollectionMembershipRow>();
  for (const row of memberships) {
    const known = firstByMember.get(row.memberId);
    if (known === undefined || row.createdAt < known.createdAt ||
      (row.createdAt === known.createdAt && row.membershipId < known.membershipId)) {
      firstByMember.set(row.memberId, row);
    }
  }
  return new Set([...firstByMember.values()].map((row) => row.membershipId));
}

type Category = 'new' | 'renewal' | 'addon' | 'unallocated';

function categoryOfPayment(row: CollectionPaymentRow, firstMemberships: Set<string>): Category {
  if (row.membershipId !== null) return firstMemberships.has(row.membershipId) ? 'new' : 'renewal';
  if (row.addonOrderId !== null) return 'addon';
  return 'unallocated';
}

/** OCC-009…013: monthly collected/returned/net per currency with the frozen derived classification. */
export function classifyMonthlyCollection(
  payments: ReadonlyArray<CollectionPaymentRow>,
  returns: ReadonlyArray<CollectionReturnRow>,
  memberships: ReadonlyArray<CollectionMembershipRow>,
  options?: { timeZone?: string },
): ClassifiedCollection {
  const timeZone = options?.timeZone ?? 'UTC';
  const monthOf = (instant: string): string => {
    const wall = zonedWall(Date.parse(instant), timeZone);
    return `${wall.year}-${pad2(wall.month)}`;
  };
  const firstMemberships = firstMembershipIds(memberships);
  const categoryByPayment = new Map<string, Category>();
  for (const row of payments) categoryByPayment.set(row.paymentId, categoryOfPayment(row, firstMemberships));
  const monthMap = new Map<string, {
    collected: bigint; returned: bigint;
    classification: { new: bigint; renewal: bigint; addon: bigint; unallocated: bigint; unknownReturn: bigint };
  }>();
  const monthSlot = (month: string, currency: string) => {
    const key = `${month}|${currency}`;
    let slot = monthMap.get(key);
    if (slot === undefined) {
      slot = { collected: ZERO, returned: ZERO, classification: { new: ZERO, renewal: ZERO, addon: ZERO, unallocated: ZERO, unknownReturn: ZERO } };
      monthMap.set(key, slot);
    }
    return slot;
  };
  const warnings: ClassifiedCollection['warnings'] = { undatedPayments: [], undatedReturns: [] };
  for (const row of payments) {
    if (!ARRIVED_STATUSES.has(row.status)) continue;
    if (row.paidAt === null) {
      warnings.undatedPayments.push({ paymentId: row.paymentId, amountPaise: row.amountPaise, currency: row.currency });
      continue;
    }
    const slot = monthSlot(monthOf(row.paidAt), row.currency);
    const amount = BigInt(row.amountPaise);
    slot.collected += amount;
    const category = categoryByPayment.get(row.paymentId) ?? 'unallocated';
    if (category === 'new') slot.classification.new += amount;
    else if (category === 'renewal') slot.classification.renewal += amount;
    else if (category === 'addon') slot.classification.addon += amount;
    else slot.classification.unallocated += amount;
  }
  for (const row of returns) {
    if (row.status !== 'completed') continue;
    if (row.processedAt === null) {
      warnings.undatedReturns.push({ returnId: row.returnId, amountPaise: row.amountPaise, currency: row.currency });
      continue;
    }
    const slot = monthSlot(monthOf(row.processedAt), row.currency);
    const amount = BigInt(row.amountPaise);
    slot.returned += amount;
    const original = row.originalPaymentId === undefined || row.originalPaymentId === null
      ? undefined
      : categoryByPayment.get(row.originalPaymentId);
    // Whole-receipt allocation: the return lands entirely in the original receipt's category; an
    // unallocated or unknown original stays in the unknown-allocation disclosure, never guessed.
    if (original === 'new') slot.classification.new -= amount;
    else if (original === 'renewal') slot.classification.renewal -= amount;
    else if (original === 'addon') slot.classification.addon -= amount;
    else slot.classification.unknownReturn -= amount;
  }
  const months: CollectionMonth[] = [...monthMap.entries()]
    .map(([key, slot]) => {
      const [month, currency] = key.split('|');
      return {
        month: month ?? '',
        currency: currency ?? '',
        collectedPaise: slot.collected.toString(),
        returnedPaise: slot.returned.toString(),
        netPaise: (slot.collected - slot.returned).toString(),
        classification: {
          newMemberPaise: slot.classification.new.toString(),
          renewalPaise: slot.classification.renewal.toString(),
          addonPaise: slot.classification.addon.toString(),
          unallocatedPaise: slot.classification.unallocated.toString(),
          unknownReturnPaise: slot.classification.unknownReturn.toString(),
          label: CLASSIFICATION_LABEL,
        },
      };
    })
    .sort((left, right) => left.month.localeCompare(right.month) || left.currency.localeCompare(right.currency));
  return { months, warnings };
}

export type ClassSessionRow = {
  sessionId: string;
  capacity: number;
  booked: number;
  attended?: number;
  noShow?: number;
  status: string;
  endsAt: string;
};

export type BookedFillSummary = {
  cohortSessions: number;
  totalCapacity: number;
  holdingBookings: number;
  bookedFillFraction: string | null;
  cancelledSessionsExcluded: number;
  attendedCount: number;
  noShowCount: number;
  unmarkedCount: number;
  markingCoverage: string | null;
  incompleteMarkingDisclosed: boolean;
  limited: boolean;
  message: string | null;
  rankings: null;
};

/** OCC-014…016: booked fill over the elapsed non-cancelled cohort — presence is never inferred. */
export function bookedFillSummary(
  sessions: ReadonlyArray<ClassSessionRow>,
  options: { asOfInstant: string; branchId?: string | null; tenantId?: string | null },
): BookedFillSummary {
  const asOf = Date.parse(options.asOfInstant);
  const cohort = sessions.filter((session) => session.status === 'scheduled' && Date.parse(session.endsAt) < asOf);
  const cancelledSessionsExcluded = sessions.filter((session) => session.status === 'cancelled').length;
  let totalCapacity = 0;
  let holdingBookings = 0;
  let attendedCount = 0;
  let noShowCount = 0;
  for (const session of cohort) {
    totalCapacity += session.capacity;
    holdingBookings += session.booked;
    attendedCount += session.attended ?? 0;
    noShowCount += session.noShow ?? 0;
  }
  const unmarkedCount = holdingBookings - attendedCount - noShowCount;
  const limited = cohort.length < OCC_LIMITS.minElapsedSessions;
  return {
    cohortSessions: cohort.length,
    totalCapacity,
    holdingBookings,
    bookedFillFraction: totalCapacity === 0 ? null : exactFractionText(holdingBookings, totalCapacity),
    cancelledSessionsExcluded,
    attendedCount,
    noShowCount,
    unmarkedCount,
    markingCoverage: holdingBookings === 0 ? null : exactFractionText(attendedCount + noShowCount, holdingBookings),
    incompleteMarkingDisclosed: unmarkedCount > 0,
    limited,
    message: limited ? 'Limited history' : null,
    rankings: null,
  };
}
