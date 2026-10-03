import { z } from 'zod';
import { Constants, type Database } from '@gymloop/db';
import { DAYS_PER_WEEK, ISO_MONTH_DAY_DIGITS, MINUTES_PER_DAY, MINUTES_PER_HOUR, MS_PER_HOUR, PT_BOOKING_LIMITS as L, PT_HTTP_STATUS as H, PT_POLICY_BOUNDS as B } from '../config/constants';
import { formatDateTime } from '../display/display';
import { toLocalDate } from '../streaks/streaks';

export function normalizeSpecialities(input: string[]): string[] {
  const seen = new Set<string>();
  return input.map((value) => value.trim()).filter((value) => {
    const key = value.toLowerCase();
    if (!value || seen.has(key)) return false;
    seen.add(key); return true;
  });
}
const reason = z.string().trim().min(L.reasonMinChars).max(L.reasonMaxChars);
const profile = { bio: z.string().trim().max(L.bioMaxChars), specialities: z.array(z.string().trim().max(L.specialityMaxChars)).transform(normalizeSpecialities).pipe(z.array(z.string().min(1).max(L.specialityMaxChars)).max(L.specialitiesMax)) };
export const ptBookRequestSchema = z.strictObject({ orderId: z.uuid(), sessionId: z.uuid(), startsAt: z.iso.datetime({ offset: true }) });
export const ptCancelRequestSchema = z.strictObject({ sessionId: z.uuid() });
export const ptGymCancelRequestSchema = z.strictObject({ sessionId: z.uuid(), reason });
export const ptWaiveRequestSchema = z.strictObject(ptGymCancelRequestSchema.shape);
export const trainerProfileRequestSchema = z.strictObject({ staffId: z.uuid(), ...profile, photoAssetId: z.uuid().nullable(), isListed: z.boolean() });
export const ownTrainerProfileRequestSchema = z.strictObject(profile);
const windowSchema = z.strictObject({ weekday: z.number().int().min(0).max(DAYS_PER_WEEK - 1), startMinute: z.number().int().min(0).max(MINUTES_PER_DAY - 1), endMinute: z.number().int().min(1).max(MINUTES_PER_DAY) }).refine((window) => window.endMinute > window.startMinute, { message: 'End time must follow start time.' });
export type TrainerWindow = z.infer<typeof windowSchema>;
export function windowsOverlap(a: TrainerWindow, b: TrainerWindow): boolean { return a.weekday === b.weekday && a.startMinute < b.endMinute && b.startMinute < a.endMinute; }
export const trainerAvailabilityRequestSchema = z.strictObject({ staffId: z.uuid(), windows: z.array(windowSchema).max(L.availabilityWindowsMax) }).superRefine(({ windows }, context) => {
  windows.forEach((window, index) => { if (windows.slice(0, index).some((other) => windowsOverlap(window, other))) context.addIssue({ code: 'custom', path: ['windows', index], message: 'These availability windows overlap.' }); });
});
export const trainerTimeOffRequestSchema = z.strictObject({ staffId: z.uuid(), startsOn: z.iso.date(), endsOn: z.iso.date(), reason: z.string().trim().max(L.timeOffReasonMaxChars).optional() }).refine((input) => input.endsOn >= input.startsOn, { path: ['endsOn'], message: 'End date must follow start date.' });
export const trainerTimeOffRemoveRequestSchema = z.strictObject({ timeOffId: z.uuid() });
export const ptReassignRequestSchema = z.strictObject({ fromStaffId: z.uuid(), toStaffId: z.uuid(), orderIds: z.array(z.uuid()).max(L.reassignBatchMax).optional(), reason }).refine((input) => input.fromStaffId !== input.toStaffId, { message: 'Choose a different trainer.' });
export const ptPolicyRequestSchema = z.strictObject({ cancelWindowHours: z.number().int().min(0).max(B.cancelWindowHoursMax), lateCancelConsumes: z.boolean(), sessionMinutes: z.number().int().min(B.sessionMinutesMin).max(B.sessionMinutesMax).multipleOf(B.sessionMinutesStep) });
export const PT_REFUSAL_COPY: Readonly<Record<string, string>> = {
  slot_taken: 'That time was just taken. Pick another time.', slot_unavailable: "That time isn't open for booking. Pick another time.", already_booked: 'You already have a session at that time.', membership_not_live: "Your membership isn't active on that day. Renew at the front desk to book.", trainer_other_branch: 'Your trainer works at a different branch. Ask the front desk to move your pack.', too_late_to_cancel: "This session has already started, so it can't be cancelled here. Ask your trainer or the front desk.", pack_unavailable: "This pack can't be used for booking right now. Ask the front desk.", trainer_unavailable: "Your trainer isn't available right now. Ask the front desk to move your pack to another trainer.", pack_spent: "You've booked or used every session in this pack.", outside_pack_dates: 'That time is outside the dates your pack covers.', booking_rate_limited: 'Too many bookings today. Try again tomorrow, or ask the front desk.', idempotency_conflict: 'That request was already used for something else. Try again.', retryable: 'Please try again.', not_found: "That isn't available.", session_closed: 'That session already finished.', invalid_request: 'That request could not be read. Reload the page and try again.', pt_failed: 'Please try again.',
};
export function ptRefusalMessage(code: string): string { return (Object.hasOwn(PT_REFUSAL_COPY, code) ? PT_REFUSAL_COPY[code] : PT_REFUSAL_COPY.not_found)!; }
const errors: Readonly<Record<string, string>> = { '42501': 'not_found', '22023': 'invalid_request', GL091: 'already_booked', GL092: 'slot_unavailable', GL093: 'membership_not_live', GL094: 'trainer_other_branch', GL095: 'too_late_to_cancel', GL096: 'slot_taken', '23P01': 'slot_taken', GL097: 'booking_rate_limited', GL052: 'idempotency_conflict', '40001': 'retryable', '40P01': 'retryable' };
const detailedErrors: Readonly<Record<string, string>> = { 'GL055:order_unavailable': 'pack_unavailable', 'GL055:trainer_unavailable': 'trainer_unavailable', 'GL058:session_budget_exhausted': 'pack_spent', 'GL058:session_outside_validity': 'outside_pack_dates', 'GL058:invalid_session_transition': 'session_closed' };
export function ptApiError(sqlstate: string, detail: string | null): { status: number; code: string } {
  const key = `${sqlstate}:${detail}`;
  const code = Object.hasOwn(errors, sqlstate) ? errors[sqlstate]! : Object.hasOwn(detailedErrors, key) ? detailedErrors[key]! : 'pt_failed';
  const status = code === 'pt_failed' ? H.failed : code === 'not_found' ? H.missing : code === 'invalid_request' ? H.invalid : code === 'booking_rate_limited' ? H.limited : H.conflict;
  return { status, code };
}
export type PtConsequenceInput = { startsAt: string; now: string; windowHours: number; lateConsumes: boolean; timezone: string };
export function ptCancellationConsequence(input: PtConsequenceInput): { late: boolean; consumes: boolean; cutoff: string; sentence: string } {
  const cutoff = new Date(Date.parse(input.startsAt) - input.windowHours * MS_PER_HOUR).toISOString();
  const late = Date.parse(input.now) > Date.parse(cutoff);
  const consumes = late && input.lateConsumes;
  return { late, consumes, cutoff, sentence: !late ? `Free to cancel until ${formatDateTime(cutoff, input.timezone)}.` : consumes ? 'This is inside your cancellation window. Cancelling will use 1 session from your pack.' : "This is inside your cancellation window. Cancelling won't use a session from your pack." };
}
export function ptBookingConsequence(input: PtConsequenceInput): string { const result = ptCancellationConsequence(input); return result.late ? result.sentence : `You can cancel for free until ${formatDateTime(result.cutoff, input.timezone)}.`; }
export function groupSlotsByLocalDay<T extends { startsAt: string; endsAt: string }>(slots: T[], timezone: string): { date: string; slots: T[] }[] {
  const groups = new Map<string, T[]>();
  for (const slot of slots) { const day = toLocalDate(new Date(slot.startsAt), timezone); const group = groups.get(day) ?? []; group.push(slot); groups.set(day, group); }
  return Array.from(groups, ([date, values]) => ({ date, slots: values }));
}
export function formatMinuteOfDay(minute: number): string { return `${String(Math.floor(minute / MINUTES_PER_HOUR)).padStart(ISO_MONTH_DAY_DIGITS, '0')}:${String(minute % MINUTES_PER_HOUR).padStart(ISO_MONTH_DAY_DIGITS, '0')}`; }
export function parseMinuteOfDay(text: string): number | null { if (!/^\d{2}:\d{2}$/.test(text)) return null; const [hour, minute] = text.split(':').map(Number); if (hour === undefined || minute === undefined || hour * MINUTES_PER_HOUR >= MINUTES_PER_DAY || minute >= MINUTES_PER_HOUR) return null; return hour * MINUTES_PER_HOUR + minute; }
const packLabels: Record<Database['public']['Enums']['pt_pack_state'], string> = { live: 'Live', fully_booked: 'Fully booked', spent: 'Spent', expired: 'Expired', closed: 'Closed' };
export function ptPackStateLabel(state: string): string { return Object.hasOwn(packLabels, state) ? packLabels[state as keyof typeof packLabels] : 'Unavailable'; }
export function ptBookingStatusLabel(status: string, consumed: boolean, placeNoun: string): string { switch (status) { case 'booked': return 'Booked'; case 'attended': return 'Attended'; case 'no_show': return 'No-show'; case 'cancelled_by_member': return consumed ? 'Cancelled late - session used' : 'Cancelled by you'; case 'cancelled_by_gym': return `Cancelled by your ${placeNoun}`; default: return 'Unavailable'; } }
export function ptCopy(nouns: { place: string; session: string; sessions: string; trainer: string }) { return { title: 'Training', sessions: `Your ${nouns.sessions}`, packs: 'Your packs', trainers: `${nouns.trainer.charAt(0).toUpperCase()}${nouns.trainer.slice(1)}s`, programmes: 'Programmes', book: `Book a ${nouns.session}`, noSessions: `You have no ${nouns.sessions} booked.`, noPacks: 'Ask the front desk about a training pack.', noTrainers: `Your ${nouns.place} hasn't added trainers yet.`, showAtDesk: 'Show at the desk', retry: 'Please try again.', offline: "You're offline. Showing what was last loaded.", confirm: 'Confirm', cancel: 'Cancel', waiting: `Waiting for your ${nouns.trainer} to record it.`, moreHistory: `More ${nouns.session} history` }; }
export type PtCopy = ReturnType<typeof ptCopy>;

const bookingStatus = z.enum(Constants.public.Enums.booking_status).exclude(['session_cancelled']);
const bookedAnswer = z.object({ session_id: z.uuid(), order_id: z.uuid(), starts_at: z.iso.datetime({ offset: true }), ends_at: z.iso.datetime({ offset: true }), status: bookingStatus, in_cancel_window: z.boolean(), replayed: z.boolean() }).transform((row) => ({ sessionId: row.session_id, orderId: row.order_id, startsAt: row.starts_at, endsAt: row.ends_at, status: row.status, inCancelWindow: row.in_cancel_window, replayed: row.replayed }));
const cancelledAnswer = z.object({ session_id: z.uuid(), status: bookingStatus, late: z.boolean(), consumed: z.boolean(), sessions_remaining: z.number().int().nonnegative(), replayed: z.boolean() }).transform((row) => ({ sessionId: row.session_id, status: row.status, late: row.late, consumed: row.consumed, sessionsRemaining: row.sessions_remaining, replayed: row.replayed }));
const gymCancelledAnswer = z.object({ session_id: z.uuid(), status: bookingStatus, replayed: z.boolean() }).transform((row) => ({ sessionId: row.session_id, status: row.status, replayed: row.replayed }));
const waivedAnswer = z.object({ session_id: z.uuid(), order_id: z.uuid(), sessions_used: z.number().int().nonnegative(), replayed: z.boolean() }).transform((row) => ({ sessionId: row.session_id, orderId: row.order_id, sessionsUsed: row.sessions_used, replayed: row.replayed }));
const reassignedAnswer = z.object({ order_id: z.uuid(), changed: z.boolean(), cancelled_sessions: z.number().int().nonnegative() }).transform((row) => ({ orderId: row.order_id, changed: row.changed, cancelledSessions: row.cancelled_sessions }));
const answerSchemas = {
  book: z.tuple([bookedAnswer]).transform(([row]) => row), cancel: z.tuple([cancelledAnswer]).transform(([row]) => row), gymCancel: z.tuple([gymCancelledAnswer]).transform(([row]) => row), waive: z.tuple([waivedAnswer]).transform(([row]) => row),
  profile: z.uuid().transform((profileId) => ({ profileId })), availability: z.number().int().nonnegative().max(L.availabilityWindowsMax).transform((windows) => ({ windows })), timeOff: z.uuid().transform((timeOffId) => ({ timeOffId })), removeTimeOff: z.null().transform(() => ({ removed: true })), policy: z.null().transform(() => ({ saved: true })), reassign: z.array(reassignedAnswer).max(L.reassignBatchMax).transform((results) => ({ results })),
};
/** Whitelist and validate RPC output; never spread a private database row. */
export function ptCommandAnswer(kind: keyof typeof answerSchemas, data: unknown): unknown | null { const parsed = answerSchemas[kind].safeParse(data); return parsed.success ? parsed.data : null; }
