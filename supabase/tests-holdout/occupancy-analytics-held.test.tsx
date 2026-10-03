// Independent OCC holdout — derived ONLY from openspec/changes/occupancy-analytics/proposal.md
// (FROZEN 2026-10-03) and docs/design/v2/occ-bar.md. The author read no visible
// suite, no implementation, no registry and no metrics contract.
//
// Seam assumption (recorded for the orchestrator): the frozen contract names no
// export, so this suite pins the contract through one pure shared view builder
// `buildOccupancyAnalyticsView`, the drill helper `occupancyDrilldown`, and the
// contract-named `OCC_LIMITS`, imported from a platform-free shared module at
// packages/shared/src/api/occupancy-analytics. If the implemented seam lands
// under different names, reconcile through a `spec:` commit — the expectations
// below, not the import paths, are the held contract. Existing shared exports
// `ratioBasisPoints`/`formatBasisPoints` are imported to prove the harness
// resolves real modules independently of the missing OCC module.
import { describe, expect, it } from 'vitest';
import {
  buildOccupancyAnalyticsView,
  occupancyDrilldown,
  OCC_LIMITS,
} from '../../packages/shared/src/api/occupancy-analytics';
import {
  formatBasisPoints,
  ratioBasisPoints,
} from '../../packages/shared/src/api/metrics';

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

type ViewInput = Parameters<typeof buildOccupancyAnalyticsView>[0];

const baseInput = (over: Partial<ViewInput> = {}): ViewInput => ({
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
} as ViewInput);

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
    expect(OCC_LIMITS.minClassElapsedSessions).toBe(10);
  });
  it('pins the default arrival range in days', () => {
    expect(OCC_LIMITS.defaultRangeDays).toBe(28);
  });
  it('exposes the ratio helpers the contract requires for percentages', () => {
    expect(ratioBasisPoints(1, 4)).toBe(2500);
    expect(formatBasisPoints(2500)).toContain('25');
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
    const cell = view.heatmap!.branches[0]!.cells.find(
      (c: { weekday: number; hour: number }) => c.weekday === 0 && c.hour === 2,
    )!;
    expect(cell.eligibleDates).toEqual(['2026-03-15']); // 03-08 hour 2 absent
    expect(cell.raw).toBe(1);
    expect(cell.fraction).toBeDefined();
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
    const cell = view.heatmap!.branches[0]!.cells.find(
      (c: { weekday: number; hour: number }) => c.weekday === 0 && c.hour === 1,
    )!;
    expect(cell.raw).toBe(3);
    expect(cell.eligibleDates).toEqual(['2026-11-01', '2026-11-08']);
    expect(cell.fraction).toBe(1.5);
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
    const hour10 = branch.cells.find((c: { hour: number }) => c.hour === 10)!;
    expect(hour10.raw).toBe(1);
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
    const anyCell = branch.cells.find(
      (c: { eligibleDates: string[] }) => c.eligibleDates.length === 2,
    );
    expect(anyCell).toBeDefined();
    expect(anyCell!.fraction).toBe(0);
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
    expect(branch.eligibleDayCount).toBe(13); // 09-20..10-02 completed = 13 days minus holiday
    const hour10 = branch.cells.find((c: { hour: number }) => c.hour === 10)!;
    expect(hour10.eligibleDates).not.toContain('2026-10-01');
    expect(hour10.raw).toBe(1);
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
    expect(view.heatmap!.branches[0]!.cells.every(
      (c: { fraction: number | undefined }) => c.fraction === undefined,
    )).toBe(true);
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
    paymentId: paymentId(n), memberId: memberId(1), membershipId,
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
    expect(oct.classification.newMemberPaise).toBe('0');
    expect(oct.classification.renewalPaise).toBe('0');
    expect(oct.returnedPaise).toBe('20000');
    expect(oct.classification.unknownReturnPaise).toBe('0');
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
    expect(oct.classification.unknownReturnPaise).toBe('12000');
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
    const view = buildOccupancyAnalyticsView(baseInput({
      sessions: [session(1, { capacity: 10 }), session(2, { capacity: 2 })],
      bookings: [
        ...[1, 2, 3, 4, 5].map((n) => ({ bookingId: bookingId(n), sessionId: sessionId(1), status: 'booked' })),
        { bookingId: bookingId(6), sessionId: sessionId(2), status: 'booked' },
        { bookingId: bookingId(7), sessionId: sessionId(2), status: 'booked' },
      ],
    }));
    // weighted: 7/12 ≈ 5833 bp; unweighted mean would be (50% + 100%)/2 = 7500 bp
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
      rangeFrom: '2026-09-01', rangeThrough: '2026-09-20', asOf: '2026-09-21T00:00:00Z',
      attendance: visits,
    }));
    const cell = view.heatmap!.branches[0]!.cells.find((c: { hour: number }) => c.hour === 15 && c.raw === 13)!;
    expect(cell.fraction).toBeUndefined();
    expect(cell.limitedHistory).toBe(true);
    expect(cell.eligibleDates.length).toBeLessThan(OCC_LIMITS.minHeatmapEligibleDates);
  });
  it('14 eligible dates with matching visits show the exact fraction', () => {
    const visits = Array.from({ length: 14 }, (_, i) => dayVisit(i + 1, 1 + i));
    const view = buildOccupancyAnalyticsView(baseInput({
      rangeFrom: '2026-09-01', rangeThrough: '2026-09-20', asOf: '2026-09-21T00:00:00Z',
      attendance: visits,
    }));
    const cell = view.heatmap!.branches[0]!.cells.find((c: { hour: number }) => c.hour === 15 && c.raw === 14)!;
    expect(cell.fraction).toBe(1);
    expect(cell.limitedHistory).toBe(false);
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
