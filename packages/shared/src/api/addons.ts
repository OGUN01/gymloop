import { z } from 'zod';
import { MS_PER_DAY, PAISE_DIGITS, PAISE_PER_RUPEE } from '../config/constants';

const canonicalUuid = z.uuid().transform((value) => value.toLowerCase());
const nullableUuid = canonicalUuid.nullable();
const nullableDisclosure = z.string().trim().min(1).nullable();
const nullablePositiveInteger = z.number().int().positive().nullable();
const nullableNonnegativeInteger = z.number().int().nonnegative().nullable();
const offsetInstant = z.iso.datetime({ offset: true });

const catalogueFields = z.object({
  kind: z.string().trim().min(1),
  name: z.string().trim().min(1),
  description: nullableDisclosure,
  pricePaise: z.string().regex(/^(?:0|[1-9][0-9]*)$/),
  validityDays: nullablePositiveInteger,
  cancellationTerms: nullableDisclosure,
  isActive: z.boolean(),
  trainerStaffId: nullableUuid,
  trainerQualification: nullableDisclosure,
  sessionCount: nullablePositiveInteger,
  stockQuantity: nullableNonnegativeInteger,
}).strict();

function validCatalogueShape(
  value: z.infer<typeof catalogueFields>,
  context: z.RefinementCtx,
): void {
  if (!value.isActive) return;

  if (
    value.description === null || value.validityDays === null ||
    value.cancellationTerms === null
  ) {
    context.addIssue({ code: 'custom', message: 'An active offer needs complete disclosure.' });
  }

  if (value.kind === 'pt_package') {
    if (
      value.trainerStaffId === null || value.trainerQualification === null ||
      value.sessionCount === null || value.stockQuantity !== null
    ) {
      context.addIssue({ code: 'custom', message: 'A PT offer needs trainer and session facts.' });
    }
    return;
  }

  if (value.kind === 'product') {
    if (
      value.stockQuantity === null || value.trainerStaffId !== null ||
      value.trainerQualification !== null || value.sessionCount !== null
    ) {
      context.addIssue({ code: 'custom', message: 'A product offer needs stock only.' });
    }
    return;
  }

  if (value.kind === 'diet_plan' && (
    value.trainerStaffId !== null || value.trainerQualification !== null ||
    value.sessionCount !== null || value.stockQuantity !== null
  )) {
    context.addIssue({ code: 'custom', message: 'A diet offer has no trainer, session, or stock facts.' });
  }
}

/** Strict caller-owned catalogue fields; currency, tax, sort order and quote version stay server-owned. */
export const addonCatalogueCreateSchema = catalogueFields.superRefine(validCatalogueShape);

/** The same complete catalogue payload plus the product selected by the URL-less update command. */
export const addonCatalogueUpdateSchema = catalogueFields.extend({
  productId: canonicalUuid,
}).superRefine(validCatalogueShape);

const optionalReason = z.string().transform((value) => {
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}).nullable();

/** The ten caller facts accepted by `record_addon_sale`, and no client-owned money or actor facts. */
export const addonSaleRequestSchema = z.object({
  memberId: canonicalUuid,
  productId: canonicalUuid,
  quantity: z.number().int().positive(),
  quoteVersion: canonicalUuid,
  trainerStaffId: nullableUuid,
  initialStartsAt: offsetInstant.nullable(),
  initialEndsAt: offsetInstant.nullable(),
  method: z.string().trim().min(1).nullable(),
  reason: optionalReason,
  idempotencyKey: canonicalUuid,
}).strict().superRefine((value, context) => {
  if ((value.initialStartsAt === null) !== (value.initialEndsAt === null)) {
    context.addIssue({ code: 'custom', message: 'A PT slot needs both start and end instants.' });
  }
});

/** The immutable PT-slot command; blank notes are explicitly represented as null. */
export const schedulePtSessionRequestSchema = z.object({
  sessionId: canonicalUuid,
  startsAt: offsetInstant,
  endsAt: offsetInstant,
  notes: optionalReason,
}).strict();

/** The terminal PT-session command. The generated enum is checked at the web edge. */
export const finishPtSessionRequestSchema = z.object({
  sessionId: canonicalUuid,
  status: z.string().trim().min(1),
}).strict();

/** An order-completion command carries no caller-selected status or other facts. */
export const completeAddonOrderRequestSchema = z.object({}).strict();

/** The immutable expected facts that authorise a desk worker to record returned cash. */
export const completeManualAddonRefundRequestSchema = z.object({
  expectedAmountPaise: z.string().regex(/^(?:0|[1-9][0-9]*)$/),
  expectedCurrency: z.string().trim().min(1),
  expectedReason: z.string().trim().min(1),
}).strict();

export const addonSaleResultSchema = z.array(z.object({
  order_id: z.uuid(),
  payment_id: z.uuid().nullable(),
  initial_session_id: z.uuid().nullable(),
  replayed: z.boolean(),
}).strict()).length(1);

export const schedulePtSessionResultSchema = z.array(z.object({
  session_id: z.uuid(),
  order_id: z.uuid(),
  replayed: z.boolean(),
}).strict()).length(1);

export const finishPtSessionResultSchema = z.array(z.object({
  session_id: z.uuid(),
  order_id: z.uuid(),
  session_status: z.string().trim().min(1),
  order_status: z.string().trim().min(1),
  replayed: z.boolean(),
}).strict()).length(1);

export const completeAddonOrderResultSchema = z.array(z.object({
  order_id: z.uuid(),
  order_status: z.string().trim().min(1),
  replayed: z.boolean(),
}).strict()).length(1);

export const completeManualAddonRefundResultSchema = z.array(z.object({
  refund_id: z.uuid(),
  order_id: z.uuid(),
  refund_status: z.string().trim().min(1),
  order_status: z.string().trim().min(1),
  processed_at: offsetInstant.nullable(),
  replayed: z.boolean(),
}).strict()).length(1);

/**
 * Turns an unsigned rupee string into exact canonical paise text without a
 * JavaScript number ever carrying the amount.
 */
export function paiseTextFromRupees(value: string): string | null {
  const matched = value.trim().match(/^(?<whole>[0-9]+)(?:\.(?<fraction>[0-9]{1,2}))?$/);
  if (!matched?.groups?.whole) return null;

  const whole = matched.groups.whole.replace(/^0+(?=[0-9])/, '');
  const fraction = (matched.groups.fraction ?? '').padEnd(PAISE_DIGITS, '0');
  return String(BigInt(whole) * BigInt(PAISE_PER_RUPEE) + BigInt(fraction));
}

type ZonedParts = { offset: string; wallTime: string };

function zonedParts(formatter: Intl.DateTimeFormat, at: Date): ZonedParts | null {
  const values = new Map(formatter.formatToParts(at).map((part) => [part.type, part.value]));
  const year = values.get('year');
  const month = values.get('month');
  const day = values.get('day');
  const hour = values.get('hour');
  const minute = values.get('minute');
  const second = values.get('second');
  const zone = values.get('timeZoneName');
  const offset = zone?.match(/^GMT(?<sign>[+-])(?<hours>[0-9]{1,2})(?::(?<minutes>[0-9]{2}))?$/)?.groups;

  if (!year || !month || !day || !hour || !minute || !second) {
    return null;
  }

  if (zone === 'GMT') return { offset: '+00:00', wallTime: `${year}-${month}-${day}T${hour}:${minute}:${second}` };
  if (!offset?.sign || !offset.hours) return null;

  const offsetMinutes = offset.minutes ?? '00';
  return {
    offset: `${offset.sign}${offset.hours.padStart(offsetMinutes.length, '0')}:${offsetMinutes}`,
    wallTime: `${year}-${month}-${day}T${hour}:${minute}:${second}`,
  };
}

/**
 * Resolves one gym-local datetime to its unique instant. The candidate offsets
 * around that local day expose both sides of a DST change: zero matches is a
 * skipped wall time and two matches is ambiguous.
 */
export function offsetInstantFromGymWallTime(value: string, timezone: string): string | null {
  const matched = value.match(/^(?<day>[0-9]{4}-[0-9]{2}-[0-9]{2})T(?<time>[0-9]{2}:[0-9]{2})(?::(?<second>[0-9]{2}))?$/);
  if (!matched?.groups?.day || !matched.groups.time) return null;

  const wallTime = `${matched.groups.day}T${matched.groups.time}:${matched.groups.second ?? '00'}`;
  const guessed = new Date(`${wallTime}Z`);
  if (Number.isNaN(guessed.getTime()) || !guessed.toISOString().startsWith(wallTime)) return null;

  let formatter: Intl.DateTimeFormat;
  try {
    formatter = new Intl.DateTimeFormat('en-CA', {
      timeZone: timezone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
      timeZoneName: 'longOffset',
    });
  } catch {
    return null;
  }

  const nearby = [
    guessed,
    new Date(guessed.getTime() - MS_PER_DAY),
    new Date(guessed.getTime() + MS_PER_DAY),
  ];
  const offsets = new Set(nearby.map((at) => zonedParts(formatter, at)?.offset).filter((offset): offset is string => offset !== undefined));
  const matches = new Set<string>();

  for (const offset of offsets) {
    const candidate = new Date(`${wallTime}${offset}`);
    const parts = Number.isNaN(candidate.getTime()) ? null : zonedParts(formatter, candidate);
    if (parts?.wallTime === wallTime && parts.offset === offset) matches.add(candidate.toISOString());
  }

  return matches.size === 1 ? [...matches][0] ?? null : null;
}
