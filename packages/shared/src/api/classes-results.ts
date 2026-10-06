import { z } from 'zod';
import { CLASS_LIMITS, DAYS_PER_WEEK } from '../config/constants';
import { BOOKING_STATUSES } from './classes';

const count = z.number().int().nonnegative();
export const classIdentifierSchema = z.uuid();
function result<T>(schema: z.ZodType<T>, data: unknown, map: (row: T) => unknown): unknown | null { const parsed = schema.safeParse(data); return parsed.success ? map(parsed.data) : null; }
function booking(data: unknown, status: (typeof BOOKING_STATUSES)[number]) { return result(z.tuple([z.object({ booking_id: z.uuid(), status: z.literal(status) })]), data, ([r]) => ({ bookingId: r.booking_id, status: r.status })); }
export function parseClassBookResult(data: unknown) { return result(z.tuple([z.object({ booking_id: z.uuid(), status: z.literal('booked'), spots_left: count })]), data, ([r]) => ({ bookingId: r.booking_id, status: r.status, spotsLeft: r.spots_left })); }
export function parseClassDeskBookResult(data: unknown) { return parseClassBookResult(data); }
export function parseClassBookingCancelResult(data: unknown) { return booking(data, 'cancelled_by_member'); }
export function parseClassDeskCancelResult(data: unknown) { return booking(data, 'cancelled_by_gym'); }
export function parseClassAttendanceResult(data: unknown, input: { bookingId: string; status: (typeof BOOKING_STATUSES)[number] }) { return result(z.enum(BOOKING_STATUSES).refine((status) => status === input.status), data, (status) => ({ bookingId: input.bookingId, status })); }
export function parseServiceResult(data: unknown) { return result(z.uuid(), data, (serviceId) => ({ serviceId })); }
export function parseServiceResultUpdate(data: unknown, serviceId: string) { return data === null ? { serviceId } : null; }
export function parseServiceActiveResult(data: unknown, input: { isActive: boolean }, serviceId: string) { return result(z.boolean(), data, (changed) => ({ serviceId, isActive: input.isActive, changed })); }
export function parseClassRulesResult(data: unknown, input: { weekdays: number[] }) { return result(z.array(z.object({ rule_id: z.uuid(), weekday: z.number().int().min(0).max(DAYS_PER_WEEK - 1), sessions_created: count })).min(1).refine((rows) => rows.length === input.weekdays.length && new Set(input.weekdays).size === input.weekdays.length && new Set(rows.map((r) => r.weekday)).size === rows.length && rows.every((r) => input.weekdays.includes(r.weekday))), data, (rows) => ({ rules: rows.map((r) => ({ ruleId: r.rule_id, weekday: r.weekday, sessionsCreated: r.sessions_created })) })); }
export function parseClassRuleUpdateResult(data: unknown, ruleId: string) { return result(z.tuple([z.object({ sessions_created: count, sessions_updated: count, sessions_removed: count, sessions_kept: count })]), data, ([r]) => ({ ruleId, sessionsCreated: r.sessions_created, sessionsUpdated: r.sessions_updated, sessionsRemoved: r.sessions_removed, sessionsKept: r.sessions_kept })); }
export function parseClassSessionResult(data: unknown) { return result(z.uuid(), data, (sessionId) => ({ sessionId })); }
export function parseClassSessionUpdateResult(data: unknown, sessionId: string) { return data === null ? { sessionId } : null; }
export function parseClassSessionCancelResult(data: unknown, sessionId: string) { return result(z.tuple([z.object({ bookings_cancelled: count, notices_written: count, notices_withheld: count, members_without_app: count })]), data, ([r]) => ({ sessionId, bookingsCancelled: r.bookings_cancelled, noticesWritten: r.notices_written, noticesWithheld: r.notices_withheld, membersWithoutApp: r.members_without_app })); }
export function parseClassSettingsResult(data: unknown) { return result(z.tuple([z.object({ class_cancel_window_hours: z.number().int().min(0).max(CLASS_LIMITS.cancelWindowMaxHours), class_allow_cross_branch: z.boolean() })]), data, ([r]) => ({ cancelWindowHours: r.class_cancel_window_hours, allowCrossBranch: r.class_allow_cross_branch })); }
export function parseMemberClassVisibilityResult(data: unknown) { return result(z.tuple([z.object({ enabled: z.boolean(), changed: z.boolean() })]), data, ([r]) => ({ enabled: r.enabled, changed: r.changed })); }
