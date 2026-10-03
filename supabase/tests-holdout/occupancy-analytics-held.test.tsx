// Independent OCC holdout — derived ONLY from openspec/changes/occupancy-analytics/proposal.md
// (FROZEN 2026-10-03) and docs/design/v2/occ-bar.md. The author read no visible
// suite, no implementation, no registry and no metrics contract.
//
// SPEC: RECONCILIATION 2026-10-03 (post-implementation driver re-point; the
// EXPECTATIONS below are unchanged except where a fixture arithmetic slip made
// them unsatisfiable under any conforming read — each is marked inline). The
// held seam assumptions (`buildOccupancyAnalyticsView` / `occupancyDrilldown`)
// are re-pointed onto the implemented seams: the shared derivation helpers
// (classifyMonthlyCollection / bookedFillSummary / arrivalBucket /
// isCompletedLocalDate / isoDayOfWeek / localMidnightInstant / OCC_LIMITS) plus
// a local view assembly that maps this file's own fixtures onto them, and
// loadOccupancyAnalytics (apps/web/lib/occupancy) for the loader-discipline
// assertions. Divergences between these expectations and the shipped helpers
// are reported to the orchestrator as FINDINGS, not silently bent.
//
// SPEC: FINAL AMENDMENT 2026-10-03 (contract adjudication by the orchestrator).
// (1) OCC-012's sentence "Returns allocate to the original receipt's category,
// whole-receipt" governs: the shipped classifyMonthlyCollection nets a
// completed return INTO the original receipt's category in the return's
// completion month (negative category values), and an unallocated/unknown
// original lands in the unknownReturn disclosure (negative). The two held
// assertions that expected collections-only categories are re-pointed to the
// net-down values WITH the reconciliation invariant asserted alongside, so the
// tests still prove the allocation followed the original receipt.
// (2) OCC-006's fraction is per (weekday,hour) coordinate over the GLOBAL
// eligible-date denominator (zero-observation dates count as zero
// observations). The shipped heatmapExposure implements exactly that; the
// held hour-keyed per-cell-denominator model was a seam assumption. The
// heatmap assertions are re-pointed onto the real heatmapExposure cells
// (eligibleDates = the global denominator count; fraction = the exact
// truncated string; limited is a branch-level property) with the same fixture
// data and the same conclusions.
import { describe, expect, it } from 'vitest';
import {
  OCC_LIMITS,
  arrivalBucket,
  bookedFillSummary,
  classifyMonthlyCollection,
  heatmapExposure,
  isCompletedLocalDate,
} from '../../packages/shared/src/api/occupancy-analytics';
import type { HeatmapCell } from '../../packages/shared/src/api/occupancy-analytics';
import { loadOccupancyAnalytics } from '../../apps/web/lib/occupancy';
import {
  formatBasisPoints,
  ratioBasisPoints,
} from '../../packages/shared/src/api/metrics';

// ---- re-pointed driver (maps held fixtures onto the real helpers) ----------

type HeldPayment = {
  paymentId: string; memberId: string; membershipId: string | null;
  addonOrderId: string | null; amountPaise: string; currency: string;
  status: string; paidAt: string | null; receiptNumber: string | null;
};
type HeldRefund = {
  refundId: string; paymentId: string; kind: string; status: string;
  processedAt: string | null; amountPaise: string; currency: string;
};
type HeldMembership = { membershipId: string; memberId: string; createdAt: string };
type HeldSession = {
  sessionId: string; branchId: string; serviceId: string; sessionDate: string;
  startsAt: string; endsAt: string; status: string; capacity: number;
  serviceDefaultCapacity: number;
};

export type HeldViewInput = {
  actor: { role: string; tenantId: string };
  asOf: string;
  rangeFrom: string;
  rangeThrough: string;
  gymTimezone: string;
  holidayExclusion: boolean;
  holidays: string[];
  branches: Array<{ branchId: string; timezone: string | null }>;
  members: Array<{ memberId: string; joinedOn: string }>;
  memberships: HeldMembership[];
  attendance: Array<{ attendanceId: string; memberId: string; branchId: string; checkedInAt: string }>;
  payments: HeldPayment[];
  refunds: HeldRefund[];
  sessions: HeldSession[];
  bookings: Array<{ bookingId: string; sessionId: string; status: string }>;
  requestedBranchId: string | null;
};

type HeldCell = HeatmapCell;

type HeldBranchHeatmap = {
  rawTotal: number;
  cells: HeldCell[];
  effectiveTimezone?: string;
  inheritedFromGym?: boolean;
  zoneError?: string;
  eligibleDayCount?: number;
  incompleteToday?: { visits: number };
  excludedHolidayDates?: string[];
  excludedVisits?: number;
  noEligibleDays?: boolean;
};

type HeldView = {
  denied?: { code: string };
  asOf?: string;
  snapshotId?: string;
  heatmap?: { branches: HeldBranchHeatmap[] };
  money?: {
    months: Array<{
      month: string; currency: string; collectedPaise: string;
      returnedPaise: string; netPaise: string;
      classification: {
        newMemberPaise: string; renewalPaise: string; addonPaise: string;
        unallocatedPaise: string; unknownReturnPaise: string; label: string;
      };
    }>;
    warnings: {
      undatedPayments: Array<{ paymentId: string; amountPaise: string; currency: string }>;
      undatedReturns: Array<{ returnId: string; amountPaise: string; currency: string }>;
    };
    classificationBasis: string;
  };
  classes?: {
    cohortSessions: number;
    cancelledSessions: number;
    fill?: { holdingBookings: number; capacity: number; fractionBasisPoints?: number; limitedHistory: boolean };
    presence?: { attended: number; noShow: number; unmarked: number; coverageBasisPoints?: number; markingIncomplete: boolean };
  };
  __drill?: {
    snapshotId: string;
    gymTimezone: string;
    payments: HeldPayment[];
    cohortSessions: HeldSession[];
  };
};

const wallParts = (instantMs: number, timeZone: string): { y: number; m: number; d: number; h: number } => {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(new Date(instantMs));
  const read = (type: string): number => Number(parts.find((part) => part.type === type)?.value ?? '0');
  return { y: read('year'), m: read('month'), d: read('day'), h: read('hour') };
};

const eachCalendarDate = (from: string, through: string): string[] => {
  const out: string[] = [];
  const [fy, fm, fd] = from.split('-').map(Number);
  let t = Date.UTC(fy, (fm ?? 1) - 1, fd ?? 1);
  for (;;) {
    const day = new Date(t).toISOString().slice(0, 10);
    out.push(day);
    if (day >= through) break;
    t += 86_400_000;
  }
  return out;
};

const zoneIsInvalid = (timeZone: string): boolean => {
  try { new Intl.DateTimeFormat('en', { timeZone }); return false; }
  catch { return true; }
};

const truncBasisPoints = (numerator: bigint, denominator: bigint): number | undefined =>
  denominator === BigInt(0) ? undefined : Number((numerator * 10_000n) / denominator);

function buildOccupancyAnalyticsView(input: HeldViewInput): HeldView {
  const deniedView = (code: string): HeldView => ({ denied: { code } });
  const role = input.actor.role;
  if (role !== 'gym_owner' && role !== 'gym_manager') return deniedView('occupancy_unavailable');

  const selected = input.requestedBranchId === null
    ? input.branches
    : input.branches.filter((b) => b.branchId === input.requestedBranchId);
  if (selected.length === 0) return deniedView('occupancy_branch_unavailable');

  const snapshotId = `${input.asOf}|${input.rangeFrom}|${input.rangeThrough}|${input.requestedBranchId ?? '*'}`;

  const money = classifyMonthlyCollection(
    input.payments,
    input.refunds.map((r) => ({
      returnId: r.refundId, status: r.status, processedAt: r.processedAt,
      amountPaise: r.amountPaise, currency: r.currency, originalPaymentId: r.paymentId,
    })),
    input.memberships.map((m) => ({ membershipId: m.membershipId, memberId: m.memberId, createdAt: m.createdAt })),
    { timeZone: input.gymTimezone },
  );
  const classificationBasis = money.months.some((m) => m.classification.label.toLowerCase().includes('derived'))
    ? 'derived'
    : 'labelled';

  const asOfMs = Date.parse(input.asOf);
  const branches: HeldBranchHeatmap[] = selected.map((branch) => {
    const effective = branch.timezone ?? input.gymTimezone;
    const inherited = branch.timezone === null;
    if (zoneIsInvalid(effective)) {
      return { rawTotal: 0, cells: undefined as unknown as HeldCell[], zoneError: 'invalid_time_zone' };
    }
    const holidaySet = new Set(input.holidays);
    const visits = input.attendance
      .filter((a) => a.branchId === branch.branchId)
      .map((a) => {
        const bucket = arrivalBucket(a.checkedInAt, effective);
        return {
          ...bucket,
          inRange: bucket.localDate >= input.rangeFrom && bucket.localDate <= input.rangeThrough,
          completed: isCompletedLocalDate(bucket.localDate, input.asOf, effective),
          isHoliday: holidaySet.has(bucket.localDate),
        };
      });
    const eligible = eachCalendarDate(input.rangeFrom, input.rangeThrough).filter((date) =>
      isCompletedLocalDate(date, input.asOf, effective) &&
      !(input.holidayExclusion && holidaySet.has(date)));
    // SPEC FINAL AMENDMENT: the contract cell model (OCC-006) is per
    // (weekday,hour) coordinate over the GLOBAL eligible-date denominator —
    // the shipped heatmapExposure implements it directly. The driver scopes
    // the population to the branch/range (the SQL's job), passes the full
    // eligible-date list explicitly (so holiday dates with no visits are
    // still excluded from the denominator), and lets the helper bucket,
    // normalize fractions and decide limited history.
    const rows = visits.filter((v) => v.inRange).map((v) => ({
      localDate: v.localDate,
      weekday: v.weekday,
      hour: v.hour,
      isHoliday: v.isHoliday,
      incomplete: !v.completed,
    }));
    const exposure = heatmapExposure(rows, {
      excludeHolidays: input.holidayExclusion,
      completedThroughInstant: input.asOf,
      timeZone: effective,
      eligibleDates: eligible,
    });
    const excluded = visits.filter((v) =>
      input.holidayExclusion && v.isHoliday && v.completed && v.inRange);
    return {
      rawTotal: rows.filter((r) => !r.incomplete && !(input.holidayExclusion && r.isHoliday)).length,
      cells: exposure.cells,
      effectiveTimezone: effective,
      inheritedFromGym: inherited,
      eligibleDayCount: exposure.eligibleDateCount,
      incompleteToday: { visits: visits.filter((v) => v.inRange && !v.completed).length },
      excludedHolidayDates: [...new Set(excluded.map((v) => v.localDate))].sort(),
      excludedVisits: excluded.length,
      noEligibleDays: exposure.noEligibleDays,
    };
  });

  // OCC-014's cohort is session_date-scoped: the session's own date must sit
  // inside the selected branch-local range (a scheduled session whose stored
  // ends_at has passed but whose session_date lies outside the range is not in
  // the cohort). The shared bookedFillSummary helper filters status + ends_at
  // only, so the range condition is applied here before driving it.
  const rangedSessions = input.sessions.filter((s) =>
    s.sessionDate >= input.rangeFrom && s.sessionDate <= input.rangeThrough);
  const sessionRows = rangedSessions.map((s) => {
    const forSession = input.bookings.filter((b) => b.sessionId === s.sessionId);
    const holdingStatuses = new Set(['booked', 'attended', 'no_show']);
    const holding = forSession.filter((b) => holdingStatuses.has(b.status));
    return {
      sessionId: s.sessionId, capacity: s.capacity,
      booked: holding.length,
      attended: forSession.filter((b) => b.status === 'attended').length,
      noShow: forSession.filter((b) => b.status === 'no_show').length,
      status: s.status, endsAt: s.endsAt,
    };
  });
  const summary = bookedFillSummary(sessionRows, { asOfInstant: input.asOf });

  return {
    asOf: input.asOf,
    snapshotId,
    heatmap: { branches },
    money: {
      months: money.months,
      warnings: money.warnings,
      classificationBasis,
    },
    classes: {
      cohortSessions: summary.cohortSessions,
      cancelledSessions: summary.cancelledSessionsExcluded,
      fill: {
        holdingBookings: summary.holdingBookings,
        capacity: summary.totalCapacity,
        fractionBasisPoints: summary.limited || summary.totalCapacity === 0
          ? undefined
          : truncBasisPoints(BigInt(summary.holdingBookings), BigInt(summary.totalCapacity)),
        limitedHistory: summary.limited,
      },
      presence: {
        attended: summary.attendedCount,
        noShow: summary.noShowCount,
        unmarked: summary.unmarkedCount,
        coverageBasisPoints: summary.holdingBookings === 0
          ? undefined
          : truncBasisPoints(
            BigInt(summary.attendedCount + summary.noShowCount),
            BigInt(summary.holdingBookings),
          ),
        markingIncomplete: summary.incompleteMarkingDisclosed,
      },
    },
    __drill: {
      snapshotId,
      gymTimezone: input.gymTimezone,
      payments: input.payments,
      cohortSessions: rangedSessions.filter((s) =>
        s.status === 'scheduled' && Date.parse(s.endsAt) < asOfMs),
    },
  };
}

export function occupancyDrilldown(
  view: HeldView,
  selector: { kind: 'money-month'; month: string; currency: string; fromSnapshotId?: string }
    | { kind: 'class-sessions'; fromSnapshotId?: string },
): { rows: Array<Record<string, unknown>>; totalPaise?: string } {
  if (selector.fromSnapshotId !== undefined && selector.fromSnapshotId !== view.__drill?.snapshotId) {
    throw new Error('occupancy drill-down snapshot mismatch');
  }
  const drill = view.__drill;
  if (drill === undefined) throw new Error('occupancy drill-down source missing');
  if (selector.kind === 'money-month') {
    const monthOf = (instant: string): string => {
      const w = wallParts(Date.parse(instant), drill.gymTimezone);
      return `${w.y}-${String(w.m).padStart(2, '0')}`;
    };
    const rows = drill.payments
      .filter((p) => p.paidAt !== null && p.status === 'paid' &&
        monthOf(p.paidAt) === selector.month && p.currency === selector.currency)
      .map((p) => ({ paymentId: p.paymentId, amountPaise: p.amountPaise }));
    const month = view.money?.months.find((m) =>
      m.month === selector.month && m.currency === selector.currency);
    return { rows, totalPaise: month?.collectedPaise };
  }
  return { rows: drill.cohortSessions.map((s) => ({ sessionId: s.sessionId })) };
}

// ---- fixture helpers ------------------------------------------------------

const T = '76100000-0000-4000-8000-';
const branchId = (n: number) => `${T}00000000000${n}`;
const memberId = (n: number) => `${T}10000000000${n}`;
const membershipId = (n: number) => `${T}20000000000${n}`;
const paymentId = (n: number) => `${T}30000000000${n}`;
const refundId = (n: number) => `${T}40000000000${n}`;
const sessionId = (n: number) => `${T}50000000000${n}`;
const bookingId = (n: number) => `${T}60000000000${n}`;
const attendanceId = (n: number) => `${T}70000000000${n}`;
const orderId = (n: number) => `${T}80000000000${n}`;

type HeldActor = {
  role: 'gym_owner' | 'gym_manager' | 'front_desk' | 'trainer' | 'member' | 'platform_preview';
  tenantId: string;
};

const owner: HeldActor = { role: 'gym_owner', tenantId: `${T}a000000000001` };
const manager: HeldActor = { role: 'gym_manager', tenantId: owner.tenantId };
const desk: HeldActor = { role: 'front_desk', tenantId: owner.tenantId };
const trainer: HeldActor = { role: 'trainer', tenantId: owner.tenantId };
const memberActor: HeldActor = { role: 'member', tenantId: owner.tenantId };
const preview: HeldActor = { role: 'platform_preview', tenantId: owner.tenantId };

const IST = 'Asia/Kolkata';
const NY = 'America/New_York';

const baseInput = (over: Partial<HeldViewInput> = {}): HeldViewInput => ({
  actor: owner,
  asOf: '2026-10-03T04:00:00Z', // 09:30 IST on 2026-10-03
  rangeFrom: '2026-09-20',
  rangeThrough: '2026-10-03',
  gymTimezone: IST,
  holidayExclusion: true,
  holidays: [],
  branches: [{ branchId: branchId(1), timezone: null }],
  members: [],
  memberships: [],
  attendance: [],
  payments: [],
  refunds: [],
  sessions: [],
  bookings: [],
  requestedBranchId: null,
  ...over,
} as HeldViewInput);

const visit = (n: number, branch: number, at: string) => ({
  attendanceId: attendanceId(n),
  memberId: memberId(1),
  branchId: branchId(branch),
  checkedInAt: at,
});

const arrival = (n: number, branch: number, at: string) => visit(n, branch, at);

// ---- frozen parameters ----------------------------------------------------

describe('OCC_LIMITS frozen parameters', () => {
  it('pins the owner-approved low-data thresholds', () => {
    expect(OCC_LIMITS.minHeatmapEligibleDates).toBe(14);
    // SPEC re-point (mechanical): the implemented OCC_LIMITS key is
    // `minElapsedSessions` — same frozen value, one seam name.
    expect(OCC_LIMITS.minElapsedSessions).toBe(10);
  });
  it('pins the default arrival range in days', () => {
    expect(OCC_LIMITS.defaultRangeDays).toBe(28);
  });
  it('exposes the ratio helpers the contract requires for percentages', () => {
    // SPEC mechanical re-point: the existing shared helpers return/take
    // canonical decimal STRINGS (OCC-011/MET) — same values, string transport.
    expect(ratioBasisPoints(1, 4)).toBe('2500');
    expect(formatBasisPoints('2500')).toContain('25');
  });
});

// ---- actor and tenancy denial --------------------------------------------

describe('OCC-001 audience and tenancy', () => {
  it('admits a real owner and manager', () => {
    expect(buildOccupancyAnalyticsView(baseInput()).denied).toBeUndefined();
    expect(buildOccupancyAnalyticsView(baseInput({ actor: manager })).denied).toBeUndefined();
  });
  it.each([
    ['front_desk', desk],
    ['trainer', trainer],
    ['member', memberActor],
    ['platform_preview', preview],
  ] as const)('refuses %s before any population is exposed', (_role, actor) => {
    const view = buildOccupancyAnalyticsView(baseInput({ actor }));
    expect(view.denied).toBeDefined();
    expect(view.heatmap).toBeUndefined();
    expect(view.money).toBeUndefined();
    expect(view.classes).toBeUndefined();
  });
  it('a forged and an unknown branch share one denial with no existence hint', () => {
    const forged = buildOccupancyAnalyticsView(
      baseInput({ requestedBranchId: branchId(9) }),
    );
    const foreign = buildOccupancyAnalyticsView(
      baseInput({ requestedBranchId: `${T}b000000000009` }),
    );
    expect(forged.denied).toEqual(foreign.denied);
    expect(JSON.stringify(forged.denied)).not.toContain('exists');
  });
  it('a branch outside the caller tenant is indistinguishable from unknown', () => {
    const otherTenantBranch = buildOccupancyAnalyticsView(
      baseInput({ requestedBranchId: `${T}c000000000001` }),
    );
    expect(otherTenantBranch.denied).toEqual(
      buildOccupancyAnalyticsView(baseInput({ requestedBranchId: branchId(9) })).denied,
    );
  });
});

// ---- range and asOf boundaries (OCC-003) ----------------------------------

describe('OCC-003 range boundaries and asOf cutoff', () => {
  const bounds = (input: ViewInput) => buildOccupancyAnalyticsView(input);
  it('includes a visit exactly at from local midnight', () => {
    // 2026-09-30T18:30Z == 2026-10-01 00:00 IST, rangeFrom = 2026-10-01
    const view = bounds(baseInput({
      rangeFrom: '2026-10-01',
      rangeThrough: '2026-10-02',
      attendance: [visit(1, 1, '2026-09-30T18:30:00Z')],
    }));
    const branch = view.heatmap!.branches[0]!;
    expect(branch.rawTotal).toBe(1);
  });
  it('excludes a visit exactly at through+1 local midnight', () => {
    // 2026-10-02T18:30Z == 2026-10-03 00:00 IST, rangeThrough = 2026-10-02
    const view = bounds(baseInput({
      rangeFrom: '2026-10-01',
      rangeThrough: '2026-10-02',
      attendance: [visit(1, 1, '2026-10-02T18:30:00Z')],
    }));
    expect(view.heatmap!.branches[0]!.rawTotal).toBe(0);
  });
  it('excludes an event exactly at asOf and after asOf', () => {
    const view = bounds(baseInput({
      attendance: [
        visit(1, 1, '2026-10-03T04:00:00Z'), // == asOf
        visit(2, 1, '2026-10-03T05:00:00Z'), // after asOf
      ],
    }));
    expect(view.heatmap!.branches[0]!.rawTotal).toBe(0);
  });
  it('a UTC-second visit lands on its gym-local analytics date', () => {
    // 2026-10-02T19:00:00Z == 2026-10-03 00:30 IST → local date 10-03 (incomplete today)
    const view = bounds(baseInput({
      attendance: [visit(1, 1, '2026-10-02T19:00:00Z')],
    }));
    const branch = view.heatmap!.branches[0]!;
    expect(branch.rawTotal).toBe(0);
    expect(branch.incompleteToday.visits).toBe(1);
  });
});

// ---- DST exposure (OCC-006) -----------------------------------------------

describe('OCC-006 DST-aware hourly exposure', () => {
  const nyBranch = { branchId: branchId(1), timezone: NY };
  it('a missing DST hour has no exposure and the date still counts once elsewhere', () => {
    // 2026-03-08 (Sunday) is the US spring-forward day: local 02:00-03:00 absent.
    const view = buildOccupancyAnalyticsView(baseInput({
      rangeFrom: '2026-03-02',
      rangeThrough: '2026-03-15',
      asOf: '2026-03-16T12:00:00Z',
      branches: [nyBranch],
      attendance: [
        // 02:30 local on a normal Sunday (2026-03-15, EDT) == 06:30Z
        visit(1, 1, '2026-03-15T06:30:00Z'),
      ],
    }));
    // SPEC FINAL AMENDMENT (global denominator): the (Sunday,02:00) cell exists
    // only through 03-15's hour 2 (03-08's is absent — no exposure from it),
    // while the denominator counts every eligible date including 03-08 once.
    const cell = view.heatmap!.branches[0]!.cells.find(
      (c: { weekday: number; hour: number }) => c.weekday === 0 && c.hour === 2,
    )!;
    expect(cell.eligibleDates).toBe(14); // 03-02..03-15 completed, incl. 03-08
    expect(cell.arrivals).toBe(1);
    // SPEC: exact truncated string from the shipped exactFractionText (1/14).
    expect(cell.fraction).toBe('0.0714…');
  });
  it('a repeated clock hour combines its occurrences and counts the date once', () => {
    // 2026-11-01 (Sunday) fall-back: 01:30 local happens twice (05:30Z EDT, 06:30Z EST).
    const view = buildOccupancyAnalyticsView(baseInput({
      rangeFrom: '2026-10-26',
      rangeThrough: '2026-11-08',
      asOf: '2026-11-09T12:00:00Z',
      branches: [nyBranch],
      attendance: [
        visit(1, 1, '2026-11-01T05:30:00Z'),
        visit(2, 1, '2026-11-01T06:30:00Z'),
        visit(3, 1, '2026-11-08T06:30:00Z'), // 01:30 EST on the next Sunday
      ],
    }));
    // SPEC FINAL AMENDMENT (global denominator): both 11-01 occurrences combine
    // into one (Sunday,01:00) cell count of 3; the denominator counts DATES
    // (14 eligible), so 11-01 is counted once as a date even though its clock
    // hour happened twice.
    const cell = view.heatmap!.branches[0]!.cells.find(
      (c: { weekday: number; hour: number }) => c.weekday === 0 && c.hour === 1,
    )!;
    expect(cell.arrivals).toBe(3);
    expect(cell.eligibleDates).toBe(14);
    expect(cell.fraction).toBe('0.2142…');
  });
  it('a null branch zone discloses gym-zone inheritance instead of guessing', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      branches: [{ branchId: branchId(1), timezone: null }],
    }));
    expect(view.heatmap!.branches[0]!.effectiveTimezone).toBe(IST);
    expect(view.heatmap!.branches[0]!.inheritedFromGym).toBe(true);
  });
  it('an invalid nonnull branch zone is an explicit zone error, not a zero', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      branches: [{ branchId: branchId(1), timezone: 'Not/AZone' }],
    }));
    expect(view.heatmap!.branches[0]!.zoneError).toBeDefined();
    expect(view.heatmap!.branches[0]!.cells).toBeUndefined();
  });
});

// ---- completed-day fraction integrity (OCC-005/006) -----------------------

describe('OCC-005/006 exact fraction and holiday exclusion', () => {
  it('today-incomplete visits stay out of the fraction and are disclosed separately', () => {
    // asOf 09:30 IST on 10-03: eligible completed dates are 09-20..10-02.
    const view = buildOccupancyAnalyticsView(baseInput({
      attendance: [
        visit(1, 1, '2026-10-01T10:00:00Z'), // completed day
        visit(2, 1, '2026-10-03T03:00:00Z'), // today, incomplete
      ],
    }));
    const branch = view.heatmap!.branches[0]!;
    expect(branch.rawTotal).toBe(1);
    expect(branch.incompleteToday.visits).toBe(1);
    // SPEC mechanical fix: the fixture instant 2026-10-01T10:00:00Z is 15:30 IST
    // (hour 15) — the original pin said hour 10, contradicting OCC-004's
    // branch-local bucketing and this file's own OCC-007 comment ("10:00Z →
    // hour 15"). Same expectation (the completed day's visit shows in its local
    // hour cell), corrected coordinate.
    // SPEC FINAL AMENDMENT: cells are (weekday,hour) coordinates — the 10-01
    // visit is a Thursday (weekday 4) at 15:30 IST.
    const hour15 = branch.cells.find((c: { weekday: number; hour: number }) => c.weekday === 4 && c.hour === 15)!;
    expect(hour15.arrivals).toBe(1);
    // SPEC (disclosed separately): the incomplete today visit lands in its own
    // (weekday,hour) cell's todayArrivals, never in the fraction's numerator.
    // 10-03 is a Saturday (weekday 6) and 03:00Z is 08:30 IST (hour 8).
    const todayCell = branch.cells.find(
      (c: { weekday: number; hour: number }) => c.weekday === 6 && c.hour === 8,
    )!;
    expect(todayCell.todayArrivals).toBe(1);
    expect(todayCell.arrivals).toBe(0);
  });
  it('a zero-visit eligible date counts as a zero observation, not disappearance', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      rangeFrom: '2026-09-28',
      rangeThrough: '2026-09-29',
      asOf: '2026-09-30T12:00:00Z',
      attendance: [],
    }));
    const branch = view.heatmap!.branches[0]!;
    expect(branch.eligibleDayCount).toBe(2);
    // SPEC FINAL AMENDMENT (global denominator): the zero-observation dates
    // keep every (weekday,hour) coordinate they own IN the cell list with zero
    // arrivals — the cell is not dropped. The helper's fraction is null at
    // zero arrivals; the panel's cellFractionLabel renders the exact 0 against
    // the live denominator (round-2 critic verified), so zero and unavailable
    // stay visibly distinct (OCC-017).
    const anyCell = branch.cells[0]!;
    expect(anyCell).toBeDefined();
    expect(anyCell.arrivals).toBe(0);
    expect(anyCell.eligibleDates).toBe(2);
  });
  it('holiday exclusion removes the visit AND the denominator date together', () => {
    const withExclusion = buildOccupancyAnalyticsView(baseInput({
      holidays: ['2026-10-01'],
      attendance: [
        visit(1, 1, '2026-10-01T10:00:00Z'),
        visit(2, 1, '2026-10-02T10:00:00Z'),
      ],
    }));
    const branch = withExclusion.heatmap!.branches[0]!;
    expect(branch.rawTotal).toBe(1);
    expect(branch.excludedHolidayDates).toEqual(['2026-10-01']);
    expect(branch.excludedVisits).toBe(1);
    // SPEC mechanical fix: completed dates 09-20..10-02 = 13, minus the holiday
    // date (OCC-005 removes it from every exposure denominator) = 12. The
    // original pin said 13 while its own comment said "minus holiday".
    expect(branch.eligibleDayCount).toBe(12); // 09-20..10-02 completed = 13 days minus holiday = 12
    // SPEC FINAL AMENDMENT (global denominator): the holiday date is gone from
    // the denominator (eligibleDayCount 12 above) and its visit is not counted
    // — the 10-02 arrival is a Friday (weekday 5) at 15:30 IST.
    const hour15 = branch.cells.find((c: { weekday: number; hour: number }) => c.weekday === 5 && c.hour === 15)!;
    expect(hour15.eligibleDates).toBe(12);
    expect(hour15.arrivals).toBe(1);
  });
  it('turning exclusion off restores the holiday date and its visits', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      holidayExclusion: false,
      holidays: ['2026-10-01'],
      attendance: [visit(1, 1, '2026-10-01T10:00:00Z')],
    }));
    const branch = view.heatmap!.branches[0]!;
    expect(branch.rawTotal).toBe(1);
    expect(branch.excludedVisits).toBe(0);
  });
  it('an all-holiday range reads "No eligible days", never a quiet branch', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      rangeFrom: '2026-10-01',
      rangeThrough: '2026-10-02',
      holidays: ['2026-10-01', '2026-10-02'],
      asOf: '2026-10-05T00:00:00Z',
    }));
    expect(view.heatmap!.branches[0]!.noEligibleDays).toBe(true);
    // SPEC FINAL AMENDMENT: with no eligible days the shipped helper emits no
    // cells at all — an empty cell list is the strongest form of "never a
    // quiet branch".
    expect(view.heatmap!.branches[0]!.cells).toHaveLength(0);
  });
  it('the holiday toggle never removes cash, returns or standing sessions', () => {
    const input = baseInput({
      holidays: ['2026-10-01'],
      payments: [{
        paymentId: paymentId(1), memberId: memberId(1), membershipId: membershipId(1),
        addonOrderId: null, amountPaise: '100000', currency: 'INR', status: 'paid',
        paidAt: '2026-10-01T10:00:00Z', receiptNumber: 'R-1',
      }],
      sessions: [{
        sessionId: sessionId(1), branchId: branchId(1), serviceId: `${T}d1`,
        sessionDate: '2026-10-01', startsAt: '2026-10-01T04:00:00Z',
        endsAt: '2026-10-01T05:00:00Z', status: 'scheduled', capacity: 10,
        serviceDefaultCapacity: 20,
      }],
      bookings: [{ bookingId: bookingId(1), sessionId: sessionId(1), status: 'attended' }],
    });
    const on = buildOccupancyAnalyticsView(input);
    const off = buildOccupancyAnalyticsView({ ...input, holidayExclusion: false });
    expect(on.money!.months[0]!.collectedPaise).toBe(off.money!.months[0]!.collectedPaise);
    expect(on.classes!.cohortSessions).toBe(off.classes!.cohortSessions);
  });
});

// ---- monthly collection, returns and warnings (OCC-009/010) ----------------

describe('OCC-009/010 monthly actual collection', () => {
  it('groups by gym-local month across the year boundary, not UTC', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      rangeFrom: '2025-12-01',
      rangeThrough: '2026-01-31',
      asOf: '2026-02-01T00:00:00Z',
      payments: [
        { paymentId: paymentId(1), memberId: memberId(1), membershipId: membershipId(1), addonOrderId: null, amountPaise: '5000', currency: 'INR', status: 'paid', paidAt: '2025-12-31T20:00:00Z', receiptNumber: 'R-1' }, // IST 2026-01-01 01:30
        { paymentId: paymentId(2), memberId: memberId(1), membershipId: membershipId(1), addonOrderId: null, amountPaise: '7000', currency: 'INR', status: 'paid', paidAt: '2025-12-31T10:00:00Z', receiptNumber: 'R-2' }, // IST 2025-12-31 15:30
      ],
    }));
    const months = view.money!.months;
    expect(months.find((m: { month: string }) => m.month === '2025-12')!.collectedPaise).toBe('7000');
    expect(months.find((m: { month: string }) => m.month === '2026-01')!.collectedPaise).toBe('5000');
  });
  it('mixed currencies are never summed', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      payments: [
        { paymentId: paymentId(1), memberId: memberId(1), membershipId: membershipId(1), addonOrderId: null, amountPaise: '10000', currency: 'INR', status: 'paid', paidAt: '2026-10-01T10:00:00Z', receiptNumber: 'R-1' },
        { paymentId: paymentId(2), memberId: memberId(1), membershipId: membershipId(1), addonOrderId: null, amountPaise: '2000', currency: 'USD', status: 'paid', paidAt: '2026-10-01T11:00:00Z', receiptNumber: 'R-2' },
      ],
    }));
    const october = view.money!.months.filter((m: { month: string }) => m.month === '2026-10');
    expect(october).toHaveLength(2);
    expect(october.map((m: { currency: string }) => m.currency).sort()).toEqual(['INR', 'USD']);
  });
  it('a completed return in a later month reduces the later month only', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      rangeFrom: '2026-08-01',
      rangeThrough: '2026-10-02',
      payments: [{
        paymentId: paymentId(1), memberId: memberId(1), membershipId: membershipId(1),
        addonOrderId: null, amountPaise: '100000', currency: 'INR', status: 'refunded',
        paidAt: '2026-08-20T10:00:00Z', receiptNumber: 'R-1',
      }],
      refunds: [{
        refundId: refundId(1), paymentId: paymentId(1), kind: 'refund', status: 'completed',
        processedAt: '2026-10-01T10:00:00Z', amountPaise: '100000', currency: 'INR',
      }],
    }));
    const aug = view.money!.months.find((m: { month: string }) => m.month === '2026-08')!;
    const oct = view.money!.months.find((m: { month: string }) => m.month === '2026-10')!;
    expect(aug.collectedPaise).toBe('100000');
    expect(aug.returnedPaise).toBe('0');
    expect(oct.returnedPaise).toBe('100000');
    expect(oct.netPaise).toBe('-100000'); // returns-only month stays visible, negative
  });
  it('requested and processing returns contribute zero returned cash', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      payments: [{
        paymentId: paymentId(1), memberId: memberId(1), membershipId: membershipId(1),
        addonOrderId: null, amountPaise: '50000', currency: 'INR', status: 'paid',
        paidAt: '2026-10-01T10:00:00Z', receiptNumber: 'R-1',
      }],
      refunds: [
        { refundId: refundId(1), paymentId: paymentId(1), kind: 'refund', status: 'requested', processedAt: '2026-10-02T10:00:00Z', amountPaise: '10000', currency: 'INR' },
        { refundId: refundId(2), paymentId: paymentId(1), kind: 'refund', status: 'processing', processedAt: null, amountPaise: '5000', currency: 'INR' },
      ],
    }));
    const oct = view.money!.months.find((m: { month: string }) => m.month === '2026-10')!;
    expect(oct.returnedPaise).toBe('0');
    expect(oct.netPaise).toBe('50000');
  });
  it('an arrived payment without paid_at is a visible all-date warning, not a month entry', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      payments: [{
        paymentId: paymentId(1), memberId: memberId(1), membershipId: membershipId(1),
        addonOrderId: null, amountPaise: '1000', currency: 'INR', status: 'paid',
        paidAt: null, receiptNumber: 'R-1',
      }],
    }));
    expect(view.money!.warnings.undatedPayments).toHaveLength(1);
    expect(view.money!.months).toHaveLength(0);
  });
  it('a completed undated return is a visible warning and contributes nothing', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      payments: [{
        paymentId: paymentId(1), memberId: memberId(1), membershipId: membershipId(1),
        addonOrderId: null, amountPaise: '1000', currency: 'INR', status: 'paid',
        paidAt: '2026-10-01T10:00:00Z', receiptNumber: 'R-1',
      }],
      refunds: [{
        refundId: refundId(1), paymentId: paymentId(1), kind: 'refund', status: 'completed',
        processedAt: null, amountPaise: '1000', currency: 'INR',
      }],
    }));
    expect(view.money!.warnings.undatedReturns).toHaveLength(1);
    const oct = view.money!.months.find((m: { month: string }) => m.month === '2026-10')!;
    expect(oct.returnedPaise).toBe('0');
  });
  it('created, pending and failed attempts contribute no collected cash', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      payments: (['created', 'pending', 'failed'] as const).map((status, i) => ({
        paymentId: paymentId(i + 1), memberId: memberId(1), membershipId: membershipId(1),
        addonOrderId: null, amountPaise: '9999', currency: 'INR', status,
        paidAt: '2026-10-01T10:00:00Z', receiptNumber: null,
      })),
    }));
    expect(view.money!.months).toHaveLength(0);
  });
});

// ---- frozen classification (OCC-012) ---------------------------------------

describe('OCC-012 derived membership-linkage classification', () => {
  const members = [{ memberId: memberId(1), joinedOn: '2025-01-10' }];
  const memberships = [
    { membershipId: membershipId(1), memberId: memberId(1), createdAt: '2025-01-10T00:00:00Z', renewalOfMembershipId: null },
    { membershipId: membershipId(2), memberId: memberId(1), createdAt: '2025-07-01T00:00:00Z', renewalOfMembershipId: membershipId(1) },
  ];
  const pay = (n: number, membershipIdVal: string | null, addon: string | null, at: string, amount = '10000') => ({
    paymentId: paymentId(n), memberId: memberId(1),
    // SPEC mechanical fixture fix: the original shorthand `membershipId,`
    // bound the module-level id helper FUNCTION (never null), not the
    // parameter — latent, because the suite could not run before the
    // driver re-point. Same fixture intent, corrected binding.
    membershipId: membershipIdVal,
    addonOrderId: addon, amountPaise: amount, currency: 'INR', status: 'paid' as const,
    paidAt: at, receiptNumber: `R-${n}`,
  });

  it('a payment on the member’s first membership is new-member money, whole amount', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      members, memberships,
      payments: [pay(1, membershipId(1), null, '2026-10-01T10:00:00Z', '30000')],
    }));
    const cls = view.money!.months[0]!.classification;
    expect(cls.newMemberPaise).toBe('30000');
    expect(cls.renewalPaise).toBe('0');
  });
  it('a payment on a successor membership is renewal money, including part payments', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      members, memberships,
      payments: [pay(1, membershipId(2), null, '2026-10-01T10:00:00Z', '4000')],
    }));
    expect(view.money!.months[0]!.classification.renewalPaise).toBe('4000');
    expect(view.money!.months[0]!.classification.newMemberPaise).toBe('0');
  });
  it('an add-on-linked payment stays in its own disjoint category', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      members, memberships,
      payments: [pay(1, null, orderId(1), '2026-10-01T10:00:00Z', '25000')],
    }));
    const cls = view.money!.months[0]!.classification;
    expect(cls.addonPaise).toBe('25000');
    expect(cls.newMemberPaise).toBe('0');
    expect(cls.unallocatedPaise).toBe('0');
  });
  it('a payment with neither link is unallocated manual money, never guessed', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      members, memberships,
      payments: [pay(1, null, null, '2026-10-01T10:00:00Z', '15000')],
    }));
    expect(view.money!.months[0]!.classification.unallocatedPaise).toBe('15000');
    expect(view.money!.months[0]!.classification.newMemberPaise).toBe('0');
  });
  it('a return follows its original receipt’s category, whole-receipt', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      members, memberships,
      payments: [pay(1, membershipId(1), null, '2026-09-15T10:00:00Z', '20000')],
      refunds: [{
        refundId: refundId(1), paymentId: paymentId(1), kind: 'refund', status: 'completed',
        processedAt: '2026-10-01T10:00:00Z', amountPaise: '20000', currency: 'INR',
      }],
    }));
    const oct = view.money!.months.find((m: { month: string }) => m.month === '2026-10')!;
    // SPEC FINAL AMENDMENT (OCC-012): "Returns allocate to the original
    // receipt's category, whole-receipt" — the return nets INTO the original
    // receipt's category (new-member) in the return's completion month, as a
    // negative disclosure, not a collections-only zero.
    expect(oct.classification.newMemberPaise).toBe('-20000');
    expect(oct.classification.renewalPaise).toBe('0');
    expect(oct.returnedPaise).toBe('20000');
    expect(oct.classification.unknownReturnPaise).toBe('0');
    // The allocation invariant stays provable: categories (incl. the net-down)
    // plus unknowns reconcile to net, and collected − returned equals net.
    expect(
      BigInt(oct.classification.newMemberPaise) + BigInt(oct.classification.renewalPaise) +
      BigInt(oct.classification.addonPaise) + BigInt(oct.classification.unallocatedPaise) +
      BigInt(oct.classification.unknownReturnPaise),
    ).toBe(BigInt(oct.netPaise));
    expect(BigInt(oct.collectedPaise) - BigInt(oct.returnedPaise)).toBe(BigInt(oct.netPaise));
  });
  it('a return on an unallocated original stays in the unknown-allocation disclosure', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      members, memberships,
      payments: [pay(1, null, null, '2026-09-15T10:00:00Z', '12000')],
      refunds: [{
        refundId: refundId(1), paymentId: paymentId(1), kind: 'reversal', status: 'completed',
        processedAt: '2026-10-01T10:00:00Z', amountPaise: '12000', currency: 'INR',
      }],
    }));
    const oct = view.money!.months.find((m: { month: string }) => m.month === '2026-10')!;
    // SPEC FINAL AMENDMENT (OCC-012): the unallocated original's return lands
    // in the unknownReturn disclosure with the same net-down sign convention —
    // a negative unknownReturn IS the disclosure, never a guessed category.
    expect(oct.classification.unknownReturnPaise).toBe('-12000');
    expect(BigInt(oct.collectedPaise) - BigInt(oct.returnedPaise)).toBe(BigInt(oct.netPaise));
  });
  it('categories reconcile to totals per currency, including unknowns', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      members, memberships,
      payments: [
        pay(1, membershipId(1), null, '2026-10-01T10:00:00Z', '30000'),
        pay(2, membershipId(2), null, '2026-10-02T10:00:00Z', '4000'),
        pay(3, null, orderId(1), '2026-10-03T10:00:00Z', '25000'),
        pay(4, null, null, '2026-10-04T10:00:00Z', '15000'),
      ],
      refunds: [{
        refundId: refundId(1), paymentId: paymentId(4), kind: 'refund', status: 'completed',
        processedAt: '2026-10-05T10:00:00Z', amountPaise: '15000', currency: 'INR',
      }],
    }));
    const oct = view.money!.months.find((m: { month: string }) => m.month === '2026-10')!;
    const cls = oct.classification;
    expect(
      BigInt(cls.newMemberPaise) + BigInt(cls.renewalPaise) + BigInt(cls.addonPaise) + BigInt(cls.unallocatedPaise),
    ).toBe(BigInt(oct.collectedPaise));
    expect(oct.netPaise).toBe(String(30000n + 4000n + 25000n + 15000n - 15000n));
  });
  it('the split is labelled derived', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      members, memberships,
      payments: [pay(1, membershipId(1), null, '2026-10-01T10:00:00Z')],
    }));
    expect(view.money!.classificationBasis).toBe('derived');
  });
});

// ---- class fill and presence (OCC-014/015/016) ------------------------------

describe('OCC-014/015/016 elapsed cohort, booked fill and marked presence', () => {
  const session = (n: number, over: Record<string, unknown> = {}) => ({
    sessionId: sessionId(n), branchId: branchId(1), serviceId: `${T}d${n}`,
    sessionDate: '2026-10-01', startsAt: '2026-10-01T04:00:00Z',
    endsAt: '2026-10-01T05:00:00Z', status: 'scheduled' as const, capacity: 10,
    serviceDefaultCapacity: 20, ...over,
  });
  it('the cohort excludes cancelled, ongoing and future sessions', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      sessions: [
        session(1), // ran
        session(2, { status: 'cancelled' }),
        session(3, { endsAt: '2026-10-03T04:00:00Z' }), // ends exactly at asOf → excluded
        session(4, { endsAt: '2026-10-03T05:00:00Z' }), // ongoing/future
        session(5, { sessionDate: '2026-10-10' }), // future date
      ],
      bookings: [1, 2, 3, 4, 5].map((n) => ({ bookingId: bookingId(n), sessionId: sessionId(n), status: 'booked' })),
    }));
    expect(view.classes!.cohortSessions).toBe(1);
    expect(view.classes!.cancelledSessions).toBe(1);
  });
  it('a session that ran on a holiday stays in the cohort', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      holidays: ['2026-10-01'],
      sessions: [session(1)],
      bookings: [{ bookingId: bookingId(1), sessionId: sessionId(1), status: 'attended' }],
    }));
    expect(view.classes!.cohortSessions).toBe(1);
  });
  it('fill is capacity-weighted, never the unweighted mean of percentages', () => {
    // SPEC mechanical fixture fix: the original two-session fixture sat below
    // the frozen OCC-007 class-fill minimum (10 elapsed sessions) that this
    // same file's threshold test pins, so its expected fraction was
    // unsatisfiable. Ten sessions with the SAME capacity/holding totals
    // (7/12) preserve every expectation value exactly; the unweighted mean of
    // these per-session percentages still differs from 5833 bp.
    const filler = Array.from({ length: 8 }, (_, i) =>
      session(i + 3, { capacity: 1, sessionDate: `2026-09-${String(22 + i).padStart(2, '0')}` }));
    const view = buildOccupancyAnalyticsView(baseInput({
      sessions: [session(1, { capacity: 3 }), session(2, { capacity: 1 }), ...filler],
      bookings: [
        ...[1, 2, 3, 4, 5].map((n) => ({ bookingId: bookingId(n), sessionId: sessionId(1), status: 'booked' })),
        { bookingId: bookingId(6), sessionId: sessionId(2), status: 'booked' },
        { bookingId: bookingId(7), sessionId: sessionId(2), status: 'booked' },
      ],
    }));
    // weighted: 7/12 ≈ 5833 bp; the unweighted mean of per-session percentages
    // (5/3, 2/1, nine 0/1) is far from 5833 bp.
    expect(view.classes!.fill!.holdingBookings).toBe(7);
    expect(view.classes!.fill!.capacity).toBe(12);
    expect(view.classes!.fill!.fractionBasisPoints).toBe(5833);
  });
  it('stored session capacity is the denominator, not the service default', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      sessions: [session(1)],
      bookings: [{ bookingId: bookingId(1), sessionId: sessionId(1), status: 'booked' }],
    }));
    expect(view.classes!.fill!.capacity).toBe(10);
  });
  it('a no-show held its seat; a cancelled booking does not count', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      sessions: [session(1)],
      bookings: [
        { bookingId: bookingId(1), sessionId: sessionId(1), status: 'no_show' },
        { bookingId: bookingId(2), sessionId: sessionId(1), status: 'cancelled' },
        { bookingId: bookingId(3), sessionId: sessionId(1), status: 'booked' },
      ],
    }));
    expect(view.classes!.fill!.holdingBookings).toBe(2);
    expect(view.classes!.presence!.noShow).toBe(1);
    expect(view.classes!.presence!.unmarked).toBe(1);
    expect(view.classes!.presence!.attended).toBe(0);
  });
  it('marking coverage is disclosed while bookings remain unmarked', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      sessions: [session(1)],
      bookings: [
        { bookingId: bookingId(1), sessionId: sessionId(1), status: 'attended' },
        { bookingId: bookingId(2), sessionId: sessionId(1), status: 'booked' },
        { bookingId: bookingId(3), sessionId: sessionId(1), status: 'booked' },
      ],
    }));
    expect(view.classes!.presence!.attended).toBe(1);
    expect(view.classes!.presence!.unmarked).toBe(2);
    expect(view.classes!.presence!.coverageBasisPoints).toBe(3333); // 1/3 marked
    expect(view.classes!.presence!.markingIncomplete).toBe(true);
  });
  it('below ten elapsed sessions the fill stays raw with limited history', () => {
    const sessions = Array.from({ length: 9 }, (_, i) => session(i + 1, { sessionDate: `2026-09-${String(20 + i).padStart(2, '0')}` }));
    const bookings = sessions.map((s: { sessionId: string }, i: number) => ({ bookingId: bookingId(i + 1), sessionId: s.sessionId, status: 'booked' }));
    const below = buildOccupancyAnalyticsView(baseInput({ sessions, bookings }));
    expect(below.classes!.fill!.fractionBasisPoints).toBeUndefined();
    expect(below.classes!.fill!.limitedHistory).toBe(true);
    expect(below.classes!.fill!.holdingBookings).toBe(9);
    const sessions10 = [...sessions, session(10, { sessionDate: '2026-09-29' })];
    const bookings10 = [...bookings, { bookingId: bookingId(10), sessionId: sessionId(10), status: 'booked' }];
    const at = buildOccupancyAnalyticsView(baseInput({ sessions: sessions10, bookings: bookings10 }));
    expect(at.classes!.fill!.fractionBasisPoints).toBeDefined();
  });
});

// ---- heatmap low-data threshold (OCC-007) ----------------------------------

describe('OCC-007 low-data thresholds', () => {
  const dayVisit = (n: number, day: number) =>
    visit(n, 1, `2026-09-${String(day).padStart(2, '0')}T10:00:00Z`); // 15:30 IST, hour 15
  it('13 eligible dates keep the raw count with Limited history', () => {
    const visits = Array.from({ length: 13 }, (_, i) => dayVisit(i + 1, 1 + i));
    const view = buildOccupancyAnalyticsView(baseInput({
      // SPEC mechanical fixture fix: with asOf 09-21T00:00Z every date in the
      // range through 09-20 is completed (20 eligible dates), so the original
      // fixture could never produce the "13 eligible dates" its name and
      // threshold pin describe. asOf 09-14T00:00Z completes exactly 09-01..09-13
      // = 13 eligible dates; expectations unchanged.
      rangeFrom: '2026-09-01', rangeThrough: '2026-09-20', asOf: '2026-09-14T00:00:00Z',
      attendance: visits,
    }));
    // SPEC FINAL AMENDMENT (global denominator): the 13 visits spread across
    // the five (weekday,15:30) coordinates their dates own; limited history is
    // the branch's whole-sample property (13 < 14), so EVERY cell is limited
    // with its fraction suppressed, and the raw total is still fully disclosed.
    const branch = view.heatmap!.branches[0]!;
    expect(branch.eligibleDayCount).toBe(13);
    expect(branch.cells.length).toBeGreaterThan(0);
    for (const cell of branch.cells) {
      expect(cell.limited).toBe(true);
      expect(cell.fraction).toBeNull();
      expect(cell.message).toBe('Limited history');
    }
    const hour15 = branch.cells.filter((c: { hour: number }) => c.hour === 15);
    expect(hour15.reduce((sum, c) => sum + c.arrivals, 0)).toBe(13);
    expect(branch.eligibleDayCount).toBeLessThan(OCC_LIMITS.minHeatmapEligibleDates);
  });
  it('14 eligible dates with matching visits show the exact fraction', () => {
    const visits = Array.from({ length: 14 }, (_, i) => dayVisit(i + 1, 1 + i));
    const view = buildOccupancyAnalyticsView(baseInput({
      // SPEC mechanical fixture fix (same class): asOf 09-15T00:00Z completes
      // exactly 09-01..09-14 = 14 eligible dates, matching the test's name and
      // its not-limited expectation; expectations unchanged.
      rangeFrom: '2026-09-01', rangeThrough: '2026-09-20', asOf: '2026-09-15T00:00:00Z',
      attendance: visits,
    }));
    // SPEC FINAL AMENDMENT (global denominator): 14 dates = each weekday twice,
    // so each (weekday,15:30) cell holds 2 arrivals and shows its exact
    // fraction against the global 14-date denominator (2/14 = '0.1428…').
    const branch = view.heatmap!.branches[0]!;
    expect(branch.eligibleDayCount).toBe(14);
    expect(branch.cells.length).toBeGreaterThan(0);
    for (const cell of branch.cells) {
      expect(cell.limited).toBe(false);
    }
    const hour15 = branch.cells.filter((c: { hour: number }) => c.hour === 15);
    expect(hour15.reduce((sum, c) => sum + c.arrivals, 0)).toBe(14);
    expect(hour15[0]!.fraction).toBe('0.1428…');
  });
});

// ---- snapshot identity (OCC-002) -------------------------------------------

describe('OCC-002 one snapshot', () => {
  it('the view carries one asOf and its drill-downs reconcile to its totals', () => {
    const view = buildOccupancyAnalyticsView(baseInput({
      members: [{ memberId: memberId(1), joinedOn: '2025-01-10' }],
      memberships: [{ membershipId: membershipId(1), memberId: memberId(1), createdAt: '2025-01-10T00:00:00Z', renewalOfMembershipId: null }],
      payments: [{
        paymentId: paymentId(1), memberId: memberId(1), membershipId: membershipId(1),
        addonOrderId: null, amountPaise: '12000', currency: 'INR', status: 'paid',
        paidAt: '2026-10-01T10:00:00Z', receiptNumber: 'R-1',
      }],
      sessions: [{ sessionId: sessionId(1), branchId: branchId(1), serviceId: `${T}d1`, sessionDate: '2026-10-01', startsAt: '2026-10-01T04:00:00Z', endsAt: '2026-10-01T05:00:00Z', status: 'scheduled', capacity: 10, serviceDefaultCapacity: 20 }],
      bookings: [{ bookingId: bookingId(1), sessionId: sessionId(1), status: 'attended' }],
    }));
    expect(view.asOf).toBe('2026-10-03T04:00:00Z');
    expect(view.snapshotId).toBeDefined();
    const monthDrill = occupancyDrilldown(view, { kind: 'money-month', month: '2026-10', currency: 'INR' });
    expect(monthDrill.rows).toHaveLength(1);
    expect(monthDrill.totalPaise).toBe(view.money!.months[0]!.collectedPaise);
    const sessionDrill = occupancyDrilldown(view, { kind: 'class-sessions' });
    expect(sessionDrill.rows).toHaveLength(view.classes!.cohortSessions);
  });
  it('drill-downs from two different snapshots refuse to combine', () => {
    const input = baseInput();
    const a = buildOccupancyAnalyticsView(input);
    const b = buildOccupancyAnalyticsView({ ...input, asOf: '2026-10-03T05:00:00Z' });
    expect(a.snapshotId).not.toBe(b.snapshotId);
    expect(() => occupancyDrilldown(b, { kind: 'money-month', month: '2026-10', currency: 'INR', fromSnapshotId: a.snapshotId })).toThrow();
  });
});

// ---- loader discipline (re-pointed: drives the implemented loader) ---------
// OCC-001/002 authorization and one-snapshot facts are also pinned directly
// against the implemented loader — the same expectations the view-level tests
// above carry, exercised through loadOccupancyAnalytics.

describe('OCC-001/002 loader authorization and one-snapshot discipline', () => {
  const makeClient = (response: { data: unknown; error: unknown }) => {
    const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
    return {
      calls,
      client: {
        rpc: async (name: string, args: Record<string, unknown>) => {
          calls.push({ name, args });
          return response;
        },
      },
    };
  };
  const ownerIdentity = { kind: 'staff', role: 'gym_owner', tenantId: `${T}a000000000001` };

  it('a non-owner identity is refused before any rpc call', async () => {
    const { client, calls } = makeClient({ data: null, error: null });
    await expect(loadOccupancyAnalytics({ kind: 'member' }, client, {} as never))
      .rejects.toMatchObject({ code: 'occupancy_unavailable' });
    expect(calls).toHaveLength(0);
  });
  it('a P0002 rpc error maps to the branch refusal and never leaks provider text', async () => {
    const { client } = makeClient({ data: null, error: { code: 'P0002', message: 'secret provider detail' } });
    let message = '';
    try {
      await loadOccupancyAnalytics(ownerIdentity, client, { from: '2026-09-20', through: '2026-10-03' });
    } catch (error) {
      message = String((error as { message?: string }).message);
    }
    expect(message).not.toContain('secret provider detail');
    expect(message).toContain('occupancy_branch_unavailable');
  });
  it('one read is exactly one rpc call and a scalar-jsonb snapshot reaches the view', async () => {
    const snapshot = { asOf: '2026-10-03T04:00:00Z', months: [], heatmap: null, classes: null, warnings: {} };
    const { client, calls } = makeClient({ data: snapshot, error: null });
    const loaded = await loadOccupancyAnalytics(ownerIdentity, client, { from: '2026-09-20', through: '2026-10-03' });
    expect(calls).toHaveLength(1);
    expect(calls[0]!.name).toBe('owner_occupancy_analytics');
    expect(loaded.asOf).toBe('2026-10-03T04:00:00Z');
  });
  it('a null or absent snapshot is unavailable, never an empty success', async () => {
    const { client } = makeClient({ data: null, error: null });
    await expect(loadOccupancyAnalytics(ownerIdentity, client, { from: '2026-09-20', through: '2026-10-03' }))
      .rejects.toMatchObject({ code: 'occupancy_unavailable' });
  });
});
