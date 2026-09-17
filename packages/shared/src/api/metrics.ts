import { z } from 'zod';
import {
  BASIS_POINT_DECIMAL_PLACES,
  BASIS_POINTS_PER_PERCENT,
  RATIO_BASIS_POINT_SCALE,
  ROUND_HALF_UP_MULTIPLIER,
} from '../config/constants';

const decimal = z.string().regex(/^(?:0|[1-9]\d*)$/);
const signedDecimal = z.string().regex(/^(?:0|-?[1-9]\d*)$/);
const text = z.string().min(1);

const moneySummary = z.object({
  currency: text,
  collectedPaise: decimal,
  returnedPaise: decimal,
  netPaise: signedDecimal,
}).strict();

const range = z.object({
  from: text,
  through: text,
  startsAt: text,
  endsBefore: text,
  mode: z.enum(['month_to_date', 'explicit']),
}).strict();

const cards = z.object({
  visitsToday: decimal,
  liveMembers: decimal,
  pausedMembers: decimal,
  openCases: decimal,
  followUpsDue: decimal,
  recovered: decimal,
  cash: z.array(moneySummary),
  renewal: z.array(z.object({ currency: text, duePaise: decimal }).strict()),
  leads: z.object({ converted: decimal, total: decimal }).strict(),
  addonCash: z.array(moneySummary),
  pt: z.object({ sessionsUsed: decimal, sessionsTotal: decimal, orders: decimal }).strict(),
}).strict();

const visit = z.object({
  attendanceId: text,
  memberId: text,
  memberName: text,
  checkedInAt: text,
}).strict();

const pause = z.object({
  pauseId: text,
  startsOn: text,
  endsOn: text,
}).strict();

const liveMembership = z.object({
  membershipId: text,
  status: text,
  startsOn: text,
  endsOn: text,
  pauses: z.array(pause),
}).strict();

const liveMember = z.object({
  memberId: text,
  memberName: text,
  memberships: z.array(liveMembership),
  paused: z.boolean(),
}).strict();

const caseRow = z.object({
  caseId: text,
  memberId: text,
  memberName: text,
  status: text,
  nextFollowUpAt: text.nullable(),
  due: z.boolean(),
}).strict();

const recovery = z.object({
  caseId: text,
  memberId: text,
  memberName: text,
  returnedAt: text,
}).strict();

const collected = z.object({
  paymentId: text,
  memberId: text,
  memberName: text,
  amountPaise: decimal,
  currency: text,
  paidAt: text,
  receiptNumber: text.nullable(),
  addonOrderId: text.nullable(),
}).strict();

const returned = z.object({
  refundId: text,
  paymentId: text,
  memberId: text,
  memberName: text,
  amountPaise: decimal,
  currency: text,
  kind: text,
  processedAt: text,
  addonOrderId: text.nullable(),
}).strict();

const renewal = z.object({
  membershipId: text,
  memberId: text,
  memberName: text,
  currency: text,
  endsOn: text,
  pricePaise: decimal,
  discountPaise: decimal,
  netPricePaise: decimal,
  periodsGranted: decimal,
  eligiblePaidPaise: decimal,
  residualPaise: signedDecimal,
  duePaise: decimal,
  receipts: z.array(z.object({ paymentId: text, amountPaise: decimal }).strict()),
}).strict();

const lead = z.object({
  leadId: text,
  fullName: text,
  createdAt: text,
  stage: text,
  convertedMemberId: text.nullable(),
  convertedAt: text.nullable(),
  converted: z.boolean(),
}).strict();

const ptOrder = z.object({
  orderId: text,
  memberId: text,
  memberName: text,
  productId: text,
  trainerStaffId: text.nullable(),
  status: text,
  cohortAt: text,
  cohortSource: z.enum(['payment', 'complimentary_sale']),
  sessionsUsed: decimal,
  sessionsTotal: decimal,
}).strict();

const warningRows = z.object({
  undatedPayments: z.array(z.object({
    paymentId: text,
    amountPaise: decimal,
    currency: text,
  }).strict()),
  undatedReturns: z.array(z.object({
    refundId: text,
    paymentId: text,
    amountPaise: decimal,
    currency: text,
  }).strict()),
  undatedPtOrders: z.array(z.object({ orderId: text, status: text }).strict()),
  incompletePtOrders: z.array(z.object({
    orderId: text,
    status: text,
    cohortAt: text.nullable(),
    sessionsUsed: decimal,
    sessionsTotal: z.null(),
  }).strict()),
}).strict();

const components = z.object({
  visits: z.array(visit),
  liveMembers: z.array(liveMember),
  cases: z.array(caseRow),
  recoveries: z.array(recovery),
  collected: z.array(collected),
  returned: z.array(returned),
  renewals: z.array(renewal),
  leads: z.array(lead),
  ptOrders: z.array(ptOrder),
}).strict();

const providerReadiness = z.object({
  push: z.object({ ready: z.literal(false), reason: z.literal('provider_unconfigured') }).strict(),
  sms: z.object({ ready: z.literal(false), reason: z.literal('outside_v1') }).strict(),
  email: z.object({ ready: z.literal(false), reason: z.literal('outside_v1') }).strict(),
  whatsappBusiness: z.object({ ready: z.literal(false), reason: z.literal('outside_v1') }).strict(),
}).strict();

const failedNotification = z.object({
  notificationId: text,
  memberId: text,
  channel: text,
  failedAt: text.nullable(),
  failedReason: text.nullable(),
}).strict();

const fleetGym = z.object({
  tenantId: text,
  name: text,
  gymCode: text,
  status: text,
  tier: text.nullable(),
  timezone: text,
  trialEndsAt: text.nullable(),
  activeMembers: decimal.nullable(),
  openCases: decimal,
  failedNotifications: decimal,
  settingsComplete: z.boolean(),
  missingSettings: z.array(text),
  ownerAccessPending: z.boolean(),
  providerReadiness,
  metricsError: z.object({ code: z.literal('invalid_gym_timezone') }).strict().nullable(),
  components: z.object({
    liveMembers: z.array(liveMember).nullable(),
    cases: z.array(caseRow),
    failedNotifications: z.array(failedNotification),
  }).strict(),
}).strict();

export const ownerMetricsSchema = z.object({
  tenantId: text,
  asOf: text,
  timezone: text,
  localToday: text,
  range,
  cards,
  components,
  warnings: warningRows,
}).strict();

export const fleetMetricsSchema = z.object({
  asOf: text,
  gyms: z.array(fleetGym),
  exceptions: z.object({
    settingsIncomplete: z.array(text),
    ownerAccessPending: z.array(text),
    providerUnavailable: z.array(text),
    trialExpired: z.array(text),
  }).strict(),
}).strict();

export type OwnerMetrics = z.infer<typeof ownerMetricsSchema>;
export type FleetMetrics = z.infer<typeof fleetMetricsSchema>;

export function ratioBasisPoints(numerator: string, denominator: string): string | null {
  const divisor = BigInt(denominator);
  if (divisor === BigInt(0)) return null;
  const scaled = BigInt(numerator) * RATIO_BASIS_POINT_SCALE;
  const quotient = scaled / divisor;
  const remainder = scaled % divisor;
  const rounded = quotient + (
    remainder * ROUND_HALF_UP_MULTIPLIER >= divisor ? BigInt(1) : BigInt(0)
  );
  return rounded.toString();
}

export function formatBasisPoints(value: string): string {
  const basisPoints = BigInt(value);
  const fraction = (basisPoints % BASIS_POINTS_PER_PERCENT)
    .toString()
    .padStart(BASIS_POINT_DECIMAL_PLACES, '0');
  return `${basisPoints / BASIS_POINTS_PER_PERCENT}.${fraction}%`;
}
