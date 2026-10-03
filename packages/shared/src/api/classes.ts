import { z } from 'zod';
import { Constants } from '@gymloop/db';
import { CLASS_LIMITS, DAYS_PER_WEEK, MS_PER_DAY } from '../config/constants';
import { isoDaySchema } from './memberships';

export const BOOKING_STATUSES = Constants.public.Enums.booking_status;
export const CLASS_SESSION_STATUSES = Constants.public.Enums.class_session_status;
export const CLASS_AVAILABILITIES = ['open', 'booked', 'full', 'closed', 'cancelled', 'membership_not_live'] as const;
export type ClassAvailability = (typeof CLASS_AVAILABILITIES)[number];
const durationMinutes = z.number().int().min(CLASS_LIMITS.durationMinMinutes).max(CLASS_LIMITS.durationMaxMinutes);
const capacity = z.number().int().min(CLASS_LIMITS.capacityMin).max(CLASS_LIMITS.capacityMax);
const reason = z.string().trim().min(CLASS_LIMITS.reasonMin).max(CLASS_LIMITS.reasonMax);
const startTime = z.string().regex(/^(?:[01]\d|2[0-3]):[0-5]\d$/);
const sessionFields = { sessionDate: isoDaySchema, startTime, durationMinutes, capacity };
export const classBookRequestSchema = z.strictObject({ sessionId: z.uuid() });
export const classBookingCancelRequestSchema = z.strictObject({ bookingId: z.uuid() });
export const classDeskBookRequestSchema = z.strictObject({ sessionId: z.uuid(), memberId: z.uuid() });
export const classDeskCancelRequestSchema = z.strictObject({ bookingId: z.uuid(), reason });
export const classAttendanceRequestSchema = z.strictObject({ bookingId: z.uuid(), status: z.enum(BOOKING_STATUSES).refine((status) => status === 'attended' || status === 'no_show' || status === 'booked') });
export const serviceRequestSchema = z.strictObject({ name: z.string().trim().min(1).max(CLASS_LIMITS.nameMax), description: z.string().trim().max(CLASS_LIMITS.descriptionMax).optional().transform((value) => value || undefined), defaultDurationMinutes: durationMinutes, defaultCapacity: capacity, sortOrder: z.number().int().min(0).max(CLASS_LIMITS.sortOrderMax).default(0) });
export const serviceActiveRequestSchema = z.strictObject({ isActive: z.boolean() });
export const classRulesRequestSchema = z.strictObject({ serviceId: z.uuid(), branchId: z.uuid(), weekdays: z.array(z.number().int().min(0).max(DAYS_PER_WEEK - 1)).min(1).max(DAYS_PER_WEEK).refine((days) => new Set(days).size === days.length), startTime, durationMinutes, capacity, trainerStaffId: z.uuid().optional(), validFrom: isoDaySchema.optional(), validUntil: isoDaySchema.optional() }).refine((input) => !input.validFrom || !input.validUntil || input.validUntil >= input.validFrom);
export const classRuleUpdateRequestSchema = z.strictObject({ durationMinutes, capacity, trainerStaffId: z.uuid().nullable(), validUntil: isoDaySchema.nullable(), isActive: z.boolean() });
export const classSessionRequestSchema = z.strictObject({ serviceId: z.uuid(), branchId: z.uuid(), ...sessionFields, trainerStaffId: z.uuid().optional() });
export const classSessionUpdateRequestSchema = z.strictObject({ ...sessionFields, trainerStaffId: z.uuid().nullable() });
export const classSessionCancelRequestSchema = z.strictObject({ reason });
export const classSettingsRequestSchema = z.strictObject({ cancelWindowHours: z.number().int().min(0).max(CLASS_LIMITS.cancelWindowMaxHours), allowCrossBranch: z.boolean() });
export const CLASS_REFUSAL_COPY = {
  class_full: 'This class is full. Pick another time, or check again later in case someone cancels.',
  already_booked: "You're already booked into this class.",
  not_bookable: "This class can't be booked any more. It may have started, been cancelled or been paused.",
  membership_not_live: 'Booking needs a current membership. Ask the front desk to renew yours, then try again.',
  other_branch: 'This class is at another branch. You can book classes at your own branch.',
  cancel_window_closed: "It's too close to the start time to cancel online. Speak to the front desk if you can't make it.",
  booking_not_cancellable: "This booking can't be cancelled any more.",
  session_not_found: "That class isn't available.", booking_not_found: "That booking isn't available.",
  offline: "You're offline. Connect and try again — bookings can't be saved offline.",
  booking_failed: 'Something went wrong and nothing was changed. Try again.',
} as const;
export type ClassRefusalCode = keyof typeof CLASS_REFUSAL_COPY;
export function classRefusalMessage(code: string): string { return Object.hasOwn(CLASS_REFUSAL_COPY, code) ? CLASS_REFUSAL_COPY[code as ClassRefusalCode] : CLASS_REFUSAL_COPY.booking_failed; }
export function classAvailabilityLabel(availability: ClassAvailability, spotsLeft: number): { word: string; tone: 'ok' | 'warn' | 'muted' | 'risk' } {
  switch (availability) {
    case 'open': return { word: `${spotsLeft} ${spotsLeft === 1 ? 'spot' : 'spots'} left`, tone: 'ok' };
    case 'booked': return { word: 'Booked', tone: 'ok' };
    case 'full': return { word: 'Full', tone: 'warn' };
    case 'closed': return { word: 'Closed', tone: 'muted' };
    case 'cancelled': return { word: 'Cancelled', tone: 'risk' };
    case 'membership_not_live': return { word: 'Membership needed', tone: 'warn' };
  }
}
export function classDayStrip(todayLocalDate: string, days: number): string[] {
  const day = isoDaySchema.parse(todayLocalDate);
  const start = new Date(`${day}T00:00:00Z`).getTime();
  return Array.from({ length: Math.max(0, Math.floor(days)) }, (_, offset) => new Date(start + offset * MS_PER_DAY).toISOString().split('T')[0]!);
}
